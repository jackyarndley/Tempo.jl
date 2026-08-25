@inline _conversion_error(from, to) = EpochConversionError(
    "cannot convert time from the timescale $(typeof(from)) to $(typeof(to)).",
)

@inline function _resolve_route(
    system::TimeSystem,
    from::AbstractTimeScale,
    to::AbstractTimeScale,
)
    from_id = timescale_alias(from)
    to_id = timescale_alias(to)
    if isnothing(from_id) || isnothing(to_id) ||
       !has_timescale(system, from_id) || !has_timescale(system, to_id)
        throw(_conversion_error(from, to))
    end
    path = get_path(timescales(system), from_id, to_id)
    isempty(path) && throw(_conversion_error(from, to))
    return path
end

@inline function _route_offset(from::TimeScaleNode, to::TimeScaleNode)
    return from.parentid == to.id ? from.ftp : to.ffp
end

function _resolved_operations(system::TimeSystem, path::Vector{Int})
    number_of_operations = length(path) - 1
    first_node = get_mappednode(system.scales, path[1])
    second_node = get_mappednode(system.scales, path[2])
    first_operation = _route_offset(first_node, second_node)
    operations = Vector{typeof(first_operation)}(undef, number_of_operations)
    operations[1] = first_operation

    current = second_node
    @inbounds for index in 2:number_of_operations
        following = get_mappednode(system.scales, path[index + 1])
        operations[index] = _route_offset(current, following)
        current = following
    end
    return operations
end

# A prepared custom route stores homogeneous, already-compiled wrappers for each supported
# scalar/dual signature. Route length is data, never a type parameter.
struct _PreparedRoute{T}
    scalar::Vector{FunctionWrapper{T,Tuple{T}}}
    dual1::Vector{FunctionWrapper{_TimeNodeFunAD1{T},Tuple{_TimeNodeFunAD1{T}}}}
    dual2::Vector{FunctionWrapper{_TimeNodeFunAD2{T},Tuple{_TimeNodeFunAD2{T}}}}
    generic::Vector{TimeNodeWrappers}
end

_wrapper_vector(::Type{T}, operations, ::Val{I}) where {T,I} =
    FunctionWrapper{T,Tuple{T}}[operation.fw[I] for operation in operations]

function _PreparedRoute(::Type{T}, operations) where {T}
    return _PreparedRoute{T}(
        _wrapper_vector(T, operations, Val(1)),
        _wrapper_vector(_TimeNodeFunAD1{T}, operations, Val(2)),
        _wrapper_vector(_TimeNodeFunAD2{T}, operations, Val(3)),
        TimeNodeWrappers[operations...],
    )
end

@inline function _evaluate_route(seconds, operations)
    result = seconds
    @inbounds for operation in operations
        result += operation(result)
    end
    return result
end

@inline function (route::_PreparedRoute{T})(seconds::N) where {T,N<:Number}
    if N === T
        return _evaluate_route(seconds, route.scalar)
    elseif N === _TimeNodeFunAD1{T}
        return _evaluate_route(seconds, route.dual1)
    elseif N === _TimeNodeFunAD2{T}
        return _evaluate_route(seconds, route.dual2)
    end
    return _evaluate_route(seconds, route.generic)
end

"""
    PreparedTimeConversion{From,To,T}

A compact callable time conversion created by [`prepare_time_conversion`](@ref). The
resolved operations are a snapshot of the system route at preparation time: later topology
changes do not alter an existing prepared conversion.
"""
struct PreparedTimeConversion{
    S1<:AbstractTimeScale,
    S2<:AbstractTimeScale,
    T<:Number,
}
    route::Union{Nothing,_PreparedRoute{T}}
end

# Defined for all scales so custom prepared callables remain inferable even though this branch
# is only selected for supported built-in pairs.
@noinline _apply_builtin(seconds, from, to) = throw(_conversion_error(from, to))
@inline _is_builtin_route(::TimeSystem, ::AbstractTimeScale, ::AbstractTimeScale) = false

@inline function (conversion::PreparedTimeConversion{S1,S2})(
    seconds::Number,
) where {S1,S2}
    S1 === S2 && return seconds
    isnothing(conversion.route) && return _apply_builtin(seconds, S1(), S2())
    return conversion.route(seconds)
end

"""
    prepare_time_conversion(system, from, to)
    prepare_time_conversion(from, to; system=TIMESCALES)

Resolve and validate a time-scale route once and return a callable
[`PreparedTimeConversion`](@ref). Repeated scalar evaluation performs no graph search or node
lookup. A prepared conversion owns a snapshot of the selected route at preparation time.

# Examples
```julia
tai_to_tdb = prepare_time_conversion(TIMESCALES, TAI, TDB)
tdb_seconds = tai_to_tdb(tai_seconds)
tdb_epoch = tai_to_tdb(tai_epoch)
```
"""
function prepare_time_conversion(
    system::TimeSystem{T},
    from::S1,
    to::S2,
) where {T,S1<:AbstractTimeScale,S2<:AbstractTimeScale}
    if S1 === S2
        return PreparedTimeConversion{S1,S2,T}(nothing)
    end

    if _is_builtin_route(system, from, to)
        return PreparedTimeConversion{S1,S2,T}(nothing)
    end

    path = _resolve_route(system, from, to)
    route = _PreparedRoute(T, _resolved_operations(system, path))
    return PreparedTimeConversion{S1,S2,T}(route)
end

function prepare_time_conversion(
    from::AbstractTimeScale,
    to::AbstractTimeScale;
    system::TimeSystem=TIMESCALES,
)
    return prepare_time_conversion(system, from, to)
end
