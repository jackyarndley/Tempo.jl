import Tempo: timescale_id, timescale_name
import DifferentiationInterface as DI
# Used only to construct the exact nested-dual signatures supported by TimeSystem wrappers.
import ForwardDiff

const AUTODIFF_BACKEND = DI.AutoForwardDiff()

@timescale PRA 101 PreparedRootTimeScale
@timescale PRB 102 PreparedBranchTimeScale
@timescale PRC 103 PreparedChildTimeScale
@timescale PRD 104 PreparedDestinationTimeScale
@timescale PRO 105 PreparedOneWayTimeScale
@timescale PRX 106 PreparedErrorTimeScale

@inline _pr_ab(seconds) =
    oftype(float(seconds), 2.0) + oftype(float(seconds), 1.0e-6) * seconds
@inline _pr_ba(seconds) = -oftype(float(seconds), 2.0)
@inline _pr_bc(seconds) =
    oftype(float(seconds), 3.0) + oftype(float(seconds), 2.0e-6) * seconds
@inline _pr_cb(seconds) = -oftype(float(seconds), 3.0)
@inline _pr_cd(seconds) = oftype(float(seconds), 4.0)
@inline _pr_dc(seconds) = -oftype(float(seconds), 4.0)
@inline _pr_ad(seconds) = oftype(float(seconds), 9.0)
@inline _pr_da(seconds) = -oftype(float(seconds), 9.0)
@inline _pr_one_way(seconds) = one(float(seconds))
_pr_programming_error(::Number) = error("intentional offset failure")

const PREPARED_SYSTEM = TimeSystem{Float64}()
add_timescale!(PREPARED_SYSTEM, PRA)
add_timescale!(PREPARED_SYSTEM, PRB, _pr_ab; parent=PRA, ftp=_pr_ba)
add_timescale!(PREPARED_SYSTEM, PRC, _pr_bc; parent=PRB, ftp=_pr_cb)
add_timescale!(PREPARED_SYSTEM, PRD, _pr_cd; parent=PRC, ftp=_pr_dc)
add_timescale!(PREPARED_SYSTEM, PRO, _pr_one_way; parent=PRD)

const DIRECT_PREPARED_SYSTEM = TimeSystem{Float64}()
add_timescale!(DIRECT_PREPARED_SYSTEM, PRA)
add_timescale!(DIRECT_PREPARED_SYSTEM, PRD, _pr_ad; parent=PRA, ftp=_pr_da)

function _reference_graph_conversion(system, seconds, from, to)
    typeof(from) === typeof(to) && return seconds
    path = Tempo.get_path(
        Tempo.timescales(system),
        timescale_id(from),
        timescale_id(to),
    )
    return Tempo.apply_offsets(system, seconds, path)
end

function _allocation_bytes(callable, value)
    callable(value)
    callable(value)
    return @allocated callable(value)
end

function _central_difference(callable, value; step=10.0)
    return (callable(value + step) - callable(value - step)) / (2step)
end

@testset "Built-in fast-path equivalence" begin
    sources = (TT, TAI, UTC, TCG, TCB, TDB, GPS)
    targets = (TT, TAI, UTC, TCG, TCB, TDB, TDBH, GPS)
    epochs = (-1.0e8, 0.0, 8.0e8)

    for seconds in epochs, from in sources, to in targets
        direct = Tempo.apply_offsets(TIMESCALES, seconds, from, to)
        reference = _reference_graph_conversion(TIMESCALES, seconds, from, to)
        @test direct == reference
    end

    # The 2016 leap second changed TAI-UTC from 36 s to 37 s.
    _, before_days = Tempo.calhms2jd(2016, 12, 31, 23, 59, 59.0)
    _, after_days = Tempo.calhms2jd(2017, 1, 1, 0, 0, 0.0)
    before = before_days * Tempo.DAY2SEC
    after = after_days * Tempo.DAY2SEC
    @test Tempo.apply_offsets(TIMESCALES, before, UTC, TAI) - before ≈ 36.0
    @test Tempo.apply_offsets(TIMESCALES, after, UTC, TAI) - after ≈ 37.0
    for seconds in (before, after), to in targets
        @test Tempo.apply_offsets(TIMESCALES, seconds, UTC, to) ==
              _reference_graph_conversion(TIMESCALES, seconds, UTC, to)
    end
end

@testset "Prepared conversion behavior" begin
    seconds = 1.0e8 + 0.25
    builtin = prepare_time_conversion(TIMESCALES, TAI, TDB)
    builtin_default = prepare_time_conversion(TAI, TDB)
    direct = prepare_time_conversion(DIRECT_PREPARED_SYSTEM, PRA, PRD)
    multihop = prepare_time_conversion(PREPARED_SYSTEM, PRA, PRD)
    reverse = prepare_time_conversion(PREPARED_SYSTEM, PRD, PRA)
    identity_conversion = prepare_time_conversion(TDBH, TDBH)

    @test @inferred(builtin(seconds)) ==
          Tempo.apply_offsets(TIMESCALES, seconds, TAI, TDB)
    @test @inferred(builtin_default(seconds)) == builtin(seconds)
    @test @inferred(direct(seconds)) ==
          Tempo.apply_offsets(DIRECT_PREPARED_SYSTEM, seconds, PRA, PRD)
    @test @inferred(multihop(seconds)) ==
          Tempo.apply_offsets(PREPARED_SYSTEM, seconds, PRA, PRD)
    @test @inferred(reverse(seconds)) ==
          Tempo.apply_offsets(PREPARED_SYSTEM, seconds, PRD, PRA)
    @test @inferred(identity_conversion(seconds)) === seconds

    epoch = Epoch(seconds, PRA)
    converted_epoch = multihop(epoch)
    @test converted_epoch isa Epoch{PreparedDestinationTimeScale}
    @test value(converted_epoch) == multihop(seconds)
    @test_throws ArgumentError multihop(Epoch(seconds, PRB))

    @test_throws EpochConversionError prepare_time_conversion(PREPARED_SYSTEM, PRO, PRA)
    @test_throws EpochConversionError prepare_time_conversion(TIMESCALES, TDBH, TT)
    @test_throws EpochConversionError prepare_time_conversion(TIMESCALES, UT1, TDB)
    @test_throws EpochConversionError Tempo.apply_offsets(TIMESCALES, seconds, TDBH, TT)
    @test_throws EpochConversionError convert(TDB, Epoch(seconds, UT1))

    error_system = TimeSystem{Float64}()
    add_timescale!(error_system, PRA)
    add_timescale!(error_system, PRX, _pr_programming_error; parent=PRA)
    @test_throws ErrorException convert(PRX, Epoch(seconds, PRA); system=error_system)

    # Route length and individual function types are data, not public type parameters.
    @test typeof(direct) === typeof(multihop)
    @test fieldtypes(typeof(multihop)) ==
          (Union{Nothing,Tempo._PreparedRoute{Float64}},)
    @test !occursin("FunctionWrapper", string(typeof(multihop)))
    @test !occursin("#", string(typeof(multihop)))

    # Explicit `system=TIMESCALES` is the same public convention as the default.
    tai_epoch = Epoch(seconds, TAI)
    @test convert(TDB, tai_epoch; system=TIMESCALES) == convert(TDB, tai_epoch)
    @test convert(TAI, tai_epoch; system=TIMESCALES) === tai_epoch
end

@testset "Generic numerical types" begin
    for NumericType in (Float32, Float64, BigFloat)
        seconds = NumericType(1.0e8 + 0.25)
        offsets = (
            Tempo.offset_tai2tt,
            Tempo.offset_tt2tai,
            Tempo.offset_tt2tcg,
            Tempo.offset_tcg2tt,
            Tempo.offset_tt2tdb,
            Tempo.offset_tdb2tt,
            Tempo.offset_tdb2tcb,
            Tempo.offset_tcb2tdb,
            Tempo.offset_tt2tdbh,
            Tempo.offset_tai2gps,
            Tempo.offset_gps2tai,
            Tempo.offset_utc2tai,
            Tempo.offset_tai2utc,
        )
        @test all(offset -> offset(seconds) isa NumericType, offsets)
        @test Tempo.apply_offsets(TIMESCALES, seconds, UTC, TDB) isa NumericType
        @test prepare_time_conversion(UTC, TDB)(seconds) isa NumericType
        @test prepare_time_conversion(PREPARED_SYSTEM, PRA, PRD)(
            convert(NumericType, seconds),
        ) isa NumericType
    end

    dual1_type = Tempo._TimeNodeFunAD1{Float64}
    dual1 = dual1_type(1.0e8 + 0.25, ForwardDiff.Partials((1.0,)))
    dual2_type = Tempo._TimeNodeFunAD2{Float64}
    dual2 = dual2_type(dual1, ForwardDiff.Partials((one(dual1),)))
    custom = prepare_time_conversion(PREPARED_SYSTEM, PRA, PRD)
    builtin = prepare_time_conversion(TAI, TDB)
    for value_with_derivatives in (dual1, dual2)
        @test typeof(custom(value_with_derivatives)) === typeof(value_with_derivatives)
        @test typeof(builtin(value_with_derivatives)) === typeof(value_with_derivatives)
        @test _allocation_bytes(custom, value_with_derivatives) == 0
        @test _allocation_bytes(builtin, value_with_derivatives) == 0
    end
end

@testset "Prepared allocation behavior" begin
    seconds = 1.0e8 + 0.25
    epoch = Epoch(seconds, TAI)
    convert_builtin(epoch) = value(convert(TDB, epoch))
    apply_builtin(value) = Tempo.apply_offsets(TIMESCALES, value, TAI, TDB)

    @test _allocation_bytes(convert_builtin, epoch) == 0
    @test _allocation_bytes(apply_builtin, seconds) == 0
    @test _allocation_bytes(prepare_time_conversion(TAI, TDB), seconds) == 0
    @test _allocation_bytes(prepare_time_conversion(UTC, TDB), seconds) == 0
    @test _allocation_bytes(
        prepare_time_conversion(PREPARED_SYSTEM, PRA, PRD), seconds,
    ) == 0
end

@testset "DifferentiationInterface behavior" begin
    seconds = 1.0e8 + 0.25
    apply_builtin(value) = Tempo.apply_offsets(TIMESCALES, value, TAI, TDB)
    convert_builtin(seconds_value) = value(convert(TDB, Epoch(seconds_value, TAI)))
    prepared_builtin = prepare_time_conversion(TAI, TDB)
    prepared_custom = prepare_time_conversion(PREPARED_SYSTEM, PRA, PRD)

    @test DI.derivative(
        seconds_value -> value(Epoch(seconds_value, TAI)),
        AUTODIFF_BACKEND,
        0.0,
    ) == 1.0
    @test DI.derivative(
        elapsed -> value(Epoch(0.25, TAI) + elapsed),
        AUTODIFF_BACKEND,
        0.0,
    ) == 1.0

    for callable in (apply_builtin, convert_builtin, prepared_builtin, Tempo.offset_tdb2tt)
        derivative = DI.derivative(callable, AUTODIFF_BACKEND, seconds)
        finite_difference = _central_difference(callable, seconds)
        @test derivative ≈ finite_difference rtol=2.0e-8 atol=2.0e-8
    end

    expected_custom_derivative = (1.0 + 1.0e-6) * (1.0 + 2.0e-6)
    @test DI.derivative(prepared_custom, AUTODIFF_BACKEND, seconds) ≈
          expected_custom_derivative rtol=1.0e-12
end
