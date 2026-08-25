######
# TT #
######

const OFFSET_TAI_TT = 32.184  # seconds 

@inline _constant_like(seconds, constant) = oftype(float(seconds), constant)

"""
    offset_tai2tt(seconds)

Return the fixed offset between [`TAI`](@ref) and [`TT`](@ref) in seconds.
"""
@inline offset_tai2tt(seconds) = _constant_like(seconds, OFFSET_TAI_TT)

"""
    offset_tt2tai(seconds)

Return the fixed offset between [`TT`](@ref) and [`TAI`](@ref) in seconds.
"""
@inline offset_tt2tai(seconds) = -_constant_like(seconds, OFFSET_TAI_TT)

#######
# TCG #
#######

const JD77_SEC = -7.25803167816e8
const LG_RATE = 6.969290134e-10

"""
    offset_tcg2tt(seconds)

Return the linear offset between [`TCG`](@ref) and [`TT`](@ref) in seconds.
"""
@inline function offset_tcg2tt(seconds)
    value = float(seconds)
    δt = value - _constant_like(value, JD77_SEC)
    return -_constant_like(value, LG_RATE) * δt
end

"""
    offset_tt2tcg(seconds)

Return the linear offset between [`TT`](@ref) and [`TCG`](@ref) in seconds.
"""
@inline function offset_tt2tcg(seconds)
    value = float(seconds)
    lg_rate = _constant_like(value, LG_RATE)
    rate = lg_rate / (one(value) - lg_rate)
    δt = value - _constant_like(value, JD77_SEC)
    return rate * δt
end

#######
# TCB #
#######

const LB_RATE = 1.550519768e-8

"""
    offset_tcb2tdb(seconds)
    
Return the linear offset between [`TCB`](@ref) and [`TDB`](@ref) in seconds.
"""
@inline function offset_tcb2tdb(seconds)
    value = float(seconds)
    δt = value - _constant_like(value, JD77_SEC)
    return -_constant_like(value, LB_RATE) * δt
end

"""
    offset_tdb2tcb(seconds)
    
Return the linear offset between [`TDB`](@ref) and [`TCB`](@ref) in seconds.
"""
@inline function offset_tdb2tcb(seconds)
    value = float(seconds)
    lb_rate = _constant_like(value, LB_RATE)
    rate = lb_rate / (one(value) - lb_rate)
    δt = value - _constant_like(value, JD77_SEC)
    return rate * δt
end

#######
# TDB #
#######

const k = 1.657e-3
const eb = 1.671e-2
const m₀ = 6.239996
const m₁ = 1.99096871e-7

"""
    offset_tt2tdb(seconds)

Return the offset between [`TT`](@ref) and [`TDB`](@ref) in seconds.
This routine is accurate to ~40 microseconds over the interval 1900-2100.

!!! note
    An accurate transformation between TDB and TT depends on the trajectory of the observer. 
    For two observers fixed on Earth's surface the quantity TDB-TT can differ by as much 
    as ~4 microseconds.

### References 
- https://www.cv.nrao.edu/~rfisher/Ephemerides/times.html#TDB
- [Issue #26](https://github.com/JuliaAstro/AstroTime.jl/issues/26)
"""
@inline function offset_tt2tdb(seconds)
    value = float(seconds)
    g = _constant_like(value, m₀) + _constant_like(value, m₁) * value
    return _constant_like(value, k) * sin(g + _constant_like(value, eb) * sin(g))
end

"""
    offset_tdb2tt(seconds)

Return the offset between [`TDB`](@ref) and [`TT`](@ref) in seconds.
This routine is accurate to ~40 microseconds over the interval 1900-2100.

!!! note
    An accurate transformation between TDB and TT depends on the trajectory of the observer. 
    For two observers fixed on Earth's surface the quantity TDB-TT can differ by as much 
    as ~4 microseconds.

### References 
- https://www.cv.nrao.edu/~rfisher/Ephemerides/times.html#TDB
- [Issue #26](https://github.com/JuliaAstro/AstroTime.jl/issues/26)
"""
@inline function offset_tdb2tt(seconds)
    value = float(seconds)
    tt = value
    offset = zero(value)
    for _ in 1:3
        g = _constant_like(value, m₀) + _constant_like(value, m₁) * tt
        offset = -_constant_like(value, k) *
                 sin(g + _constant_like(value, eb) * sin(g))
        tt = value + offset
    end
    return offset
end

#######
# UTC #
#######

"""
    offset_tai2utc(seconds)

Return the offset between [`TAI`](@ref) and [`UTC`](@ref) in seconds.
"""
@inline function offset_tai2utc(seconds)
    day_to_sec = _constant_like(seconds, DAY2SEC)
    tai = float(seconds) / day_to_sec
    _, utc = tai2utc(_constant_like(tai, DJ2000), tai)
    return (utc - tai) * day_to_sec
end

"""
    offset_utc2tai(seconds)

Return the offset between [`UTC`](@ref) and [`TAI`](@ref) in seconds.
"""
@inline function offset_utc2tai(seconds)
    day_to_sec = _constant_like(seconds, DAY2SEC)
    utc = float(seconds) / day_to_sec
    _, tai = utc2tai(_constant_like(utc, DJ2000), utc)
    return (tai - utc) * day_to_sec
end

########################
# TDB (high precision) #
########################

"""
    offset_tt2tdbh(seconds)

Return the offset between [`TT`](@ref) and [`TDBH`](@ref) in seconds.

The maximum error in using the above formula is about 10 µs from 1600 to 2200.
For even more precise applications, the series expansion by 
[Harada & Fukushima (2003)](https://iopscience.iop.org/article/10.1086/378909/pdf) is recommended.

### References
- The IAU Resolutions on Astronomical Reference Systems, Time Scales, and Earth Rotation Models,
    United States Naval Observatory, https://arxiv.org/pdf/astro-ph/0602086.pdf
"""
@inline function offset_tt2tdbh(seconds)
    centuries = float(seconds) / _constant_like(seconds, CENTURY2SEC)
    return _constant_like(centuries, 0.001657) *
           sin(_constant_like(centuries, 628.3076) * centuries +
               _constant_like(centuries, 6.2401)) +
           _constant_like(centuries, 0.000022) *
           sin(_constant_like(centuries, 575.3385) * centuries +
               _constant_like(centuries, 4.2970)) +
           _constant_like(centuries, 0.000014) *
           sin(_constant_like(centuries, 1256.6152) * centuries +
               _constant_like(centuries, 6.1969)) +
           _constant_like(centuries, 0.000005) *
           sin(_constant_like(centuries, 606.9777) * centuries +
               _constant_like(centuries, 4.0212)) +
           _constant_like(centuries, 0.000005) *
           sin(_constant_like(centuries, 52.9691) * centuries +
               _constant_like(centuries, 0.4444)) +
           _constant_like(centuries, 0.000002) *
           sin(_constant_like(centuries, 21.3299) * centuries +
               _constant_like(centuries, 5.5431)) +
           _constant_like(centuries, 0.000010) * centuries *
           sin(_constant_like(centuries, 628.3076) * centuries +
               _constant_like(centuries, 4.2490))
end

#######
# GPS #
#######

const OFFSET_TAI_GPS = 19  # seconds 

"""
    offset_tai2gps(seconds)

Return the fixed offset between [`TAI`](@ref) and [`GPS`](@ref) in seconds.
"""
@inline offset_tai2gps(seconds) = _constant_like(seconds, OFFSET_TAI_GPS)

"""
    offset_gps2tai(seconds)

Return the fixed offset between [`GPS`](@ref) and [`TAI`](@ref) in seconds.
"""
@inline offset_gps2tai(seconds) = -_constant_like(seconds, OFFSET_TAI_GPS)
