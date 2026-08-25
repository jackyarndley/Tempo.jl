using Tempo

import Tempo: timescale_id, timescale_name

@timescale BRA 401 BenchmarkRootTimeScale
@timescale BRB 402 BenchmarkBranchTimeScale
@timescale BRC 403 BenchmarkChildTimeScale
@timescale BRD 404 BenchmarkDestinationTimeScale

@inline _bench_one(seconds) = oftype(float(seconds), 1.0)
@inline _bench_mone(seconds) = -oftype(float(seconds), 1.0)

const BENCHMARK_SYSTEM = TimeSystem{Float64}()
add_timescale!(BENCHMARK_SYSTEM, BRA)
add_timescale!(BENCHMARK_SYSTEM, BRB, _bench_one; parent=BRA, ftp=_bench_mone)
add_timescale!(BENCHMARK_SYSTEM, BRC, _bench_one; parent=BRB, ftp=_bench_mone)
add_timescale!(BENCHMARK_SYSTEM, BRD, _bench_one; parent=BRC, ftp=_bench_mone)

function median_nanoseconds(callable, argument; samples=31, evaluations=10_000)
    timings = Vector{Float64}(undef, samples)
    result = nothing
    for sample in eachindex(timings)
        started = time_ns()
        for _ in 1:evaluations
            result = callable(argument)
        end
        timings[sample] = (time_ns() - started) / evaluations
    end
    sort!(timings)
    GC.@preserve result begin
        return timings[(samples + 1) ÷ 2]
    end
end

function allocation_count(gcstats)
    fields = fieldnames(typeof(gcstats))
    return sum(
        getfield(gcstats, name) for name in (:malloc, :realloc, :poolalloc, :bigalloc)
        if name in fields
    )
end

function allocation_stats(callable, argument)
    callable(argument)
    GC.gc()
    before = Base.gc_num()
    result = callable(argument)
    after = Base.gc_num()
    difference = Base.GC_Diff(after, before)
    GC.@preserve result begin
        return allocation_count(difference), difference.allocd
    end
end

function report_case(name, callable, argument; evaluations=10_000)
    callable(argument)
    callable(argument)
    allocations, bytes = allocation_stats(callable, argument)
    median = median_nanoseconds(callable, argument; evaluations)
    println(
        rpad(name, 28),
        " median_ns=", round(median; digits=2),
        " allocations=", allocations,
        " bytes=", bytes,
    )
end

const BENCHMARK_SECONDS = 1.0e8 + 0.25
const BENCHMARK_EPOCH = Epoch(BENCHMARK_SECONDS, TAI)
const TAI_TO_TDB = prepare_time_conversion(TAI, TDB)
const UTC_TO_TDB = prepare_time_conversion(UTC, TDB)
const CUSTOM_THREE_HOP = prepare_time_conversion(BENCHMARK_SYSTEM, BRA, BRD)

benchmark_convert(epoch) = convert(TDB, epoch)
benchmark_apply(seconds) = Tempo.apply_offsets(TIMESCALES, seconds, TAI, TDB)
benchmark_prepared_tai(seconds) = TAI_TO_TDB(seconds)
benchmark_prepared_utc(seconds) = UTC_TO_TDB(seconds)
benchmark_prepared_custom(seconds) = CUSTOM_THREE_HOP(seconds)
benchmark_prepare_builtin() = prepare_time_conversion(TIMESCALES, TAI, TDB)
benchmark_prepare_custom() = prepare_time_conversion(BENCHMARK_SYSTEM, BRA, BRD)

println("Steady-state evaluation")
report_case("convert(TDB, epoch)", benchmark_convert, BENCHMARK_EPOCH)
report_case("apply TAI -> TDB", benchmark_apply, BENCHMARK_SECONDS)
report_case("prepared TAI -> TDB", benchmark_prepared_tai, BENCHMARK_SECONDS)
report_case("prepared UTC -> TDB", benchmark_prepared_utc, BENCHMARK_SECONDS)
report_case("prepared custom 3-hop", benchmark_prepared_custom, BENCHMARK_SECONDS)

println("\nPreparation (separate from evaluation)")
report_case("prepare TAI -> TDB", _ -> benchmark_prepare_builtin(), nothing; evaluations=1_000)
report_case("prepare custom 3-hop", _ -> benchmark_prepare_custom(), nothing; evaluations=100)

println("\nFresh process")
root = normpath(joinpath(@__DIR__, ".."))
fresh_script = joinpath(@__DIR__, "fresh_process.jl")
run(`$(Base.julia_cmd()) --startup-file=no --project=$root $fresh_script`)
