const TIMESCALES_NAMES = (
    :TerrestrialTime,
    :InternationalAtomicTime,
    :CoordinatedUniversalTime,
    :GeocentricCoordinateTime,
    :BarycentricCoordinateTime,
    :BarycentricDynamicalTime,
    :UniversalTime,
    :HighPrecisionBarycentricDynamicalTime,
    :GlobalPositioningSystemTime,
)

const TIMESCALES_ACRONYMS = (:TT, :TAI, :UTC, :TCG, :TCB, :TDB, :UT1, :TDBH, :GPS)

for index in eachindex(TIMESCALES_ACRONYMS)
    @eval begin
        @timescale $(TIMESCALES_ACRONYMS[index]) $index $(TIMESCALES_NAMES[index])
        export $(TIMESCALES_ACRONYMS[index]), $(TIMESCALES_NAMES[index])
    end
end

"""
    TIMESCALES

Tempo's default time system. Its built-in topology has an internal direct evaluator;
custom [`TimeSystem`](@ref) instances retain general graph routing.
"""
const TIMESCALES = _default_time_system(Float64)

add_timescale!(TIMESCALES, TT, _zero_offset)
add_timescale!(TIMESCALES, TDB, offset_tt2tdb; parent=TT, ftp=offset_tdb2tt)
add_timescale!(TIMESCALES, TAI, offset_tt2tai; parent=TT, ftp=offset_tai2tt)
add_timescale!(TIMESCALES, TCG, offset_tt2tcg; parent=TT, ftp=offset_tcg2tt)
add_timescale!(TIMESCALES, TCB, offset_tdb2tcb; parent=TDB, ftp=offset_tcb2tdb)
add_timescale!(TIMESCALES, UTC, offset_tai2utc; parent=TAI, ftp=offset_utc2tai)
add_timescale!(TIMESCALES, TDBH, offset_tt2tdbh; parent=TT)
add_timescale!(TIMESCALES, GPS, offset_gps2tai; parent=TAI, ftp=offset_tai2gps)

const _DefaultScaleFrom = Union{
    TerrestrialTime,
    BarycentricDynamicalTime,
    InternationalAtomicTime,
    GeocentricCoordinateTime,
    BarycentricCoordinateTime,
    CoordinatedUniversalTime,
    GlobalPositioningSystemTime,
}

const _DefaultScaleTo = Union{
    _DefaultScaleFrom,
    HighPrecisionBarycentricDynamicalTime,
}

const _DefaultTAIBranch = Union{
    InternationalAtomicTime,
    CoordinatedUniversalTime,
    GlobalPositioningSystemTime,
}
const _DefaultTDBBranch = Union{
    BarycentricDynamicalTime,
    BarycentricCoordinateTime,
}

@inline _default_to_tai(seconds, ::InternationalAtomicTime) = seconds
@inline _default_to_tai(seconds, ::CoordinatedUniversalTime) =
    seconds + offset_utc2tai(seconds)
@inline _default_to_tai(seconds, ::GlobalPositioningSystemTime) =
    seconds + offset_tai2gps(seconds)

@inline _default_from_tai(seconds, ::InternationalAtomicTime) = seconds
@inline _default_from_tai(seconds, ::CoordinatedUniversalTime) =
    seconds + offset_tai2utc(seconds)
@inline _default_from_tai(seconds, ::GlobalPositioningSystemTime) =
    seconds + offset_gps2tai(seconds)

@inline _default_to_tdb(seconds, ::BarycentricDynamicalTime) = seconds
@inline _default_to_tdb(seconds, ::BarycentricCoordinateTime) =
    seconds + offset_tcb2tdb(seconds)

@inline _default_from_tdb(seconds, ::BarycentricDynamicalTime) = seconds
@inline _default_from_tdb(seconds, ::BarycentricCoordinateTime) =
    seconds + offset_tdb2tcb(seconds)

@inline _default_to_tt(seconds, ::TerrestrialTime) = seconds
@inline _default_to_tt(seconds, scale::_DefaultTAIBranch) = begin
    tai = _default_to_tai(seconds, scale)
    tai + offset_tai2tt(tai)
end
@inline _default_to_tt(seconds, ::GeocentricCoordinateTime) =
    seconds + offset_tcg2tt(seconds)
@inline _default_to_tt(seconds, scale::_DefaultTDBBranch) = begin
    tdb = _default_to_tdb(seconds, scale)
    tdb + offset_tdb2tt(tdb)
end

@inline _default_from_tt(seconds, ::TerrestrialTime) = seconds
@inline _default_from_tt(seconds, scale::_DefaultTAIBranch) = begin
    tai = seconds + offset_tt2tai(seconds)
    _default_from_tai(tai, scale)
end
@inline _default_from_tt(seconds, ::GeocentricCoordinateTime) =
    seconds + offset_tt2tcg(seconds)
@inline _default_from_tt(seconds, scale::_DefaultTDBBranch) = begin
    tdb = seconds + offset_tt2tdb(seconds)
    _default_from_tdb(tdb, scale)
end
@inline _default_from_tt(seconds, ::HighPrecisionBarycentricDynamicalTime) =
    seconds + offset_tt2tdbh(seconds)

# Branch-local conversions use their nearest common ancestor; cross-branch conversions use TT.
# This preserves graph operation order without a pair table or runtime path construction.
@inline function _apply_builtin(
    seconds,
    from::_DefaultScaleFrom,
    to::_DefaultScaleTo,
)
    typeof(from) === typeof(to) && return seconds
    if from isa _DefaultTAIBranch && to isa _DefaultTAIBranch
        return _default_from_tai(_default_to_tai(seconds, from), to)
    elseif from isa _DefaultTDBBranch && to isa _DefaultTDBBranch
        return _default_from_tdb(_default_to_tdb(seconds, from), to)
    end
    return _default_from_tt(_default_to_tt(seconds, from), to)
end

@inline function apply_offsets(
    ::TimeSystem{T,true},
    seconds::Number,
    from::_DefaultScaleFrom,
    to::_DefaultScaleTo,
) where {T}
    return _apply_builtin(seconds, from, to)
end

@inline function _is_builtin_route(
    ::TimeSystem{T,true},
    ::_DefaultScaleFrom,
    ::_DefaultScaleTo,
) where {T}
    return true
end
