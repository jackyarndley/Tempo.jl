# Function signatures stored directly by prepared time-system routes.
_TagAD1{T} = Autodiff.ForwardDiff.Tag{Autodiff.JSMDDiffTag, T}
_TimeNodeFunAD1{T} = Autodiff.ForwardDiff.Dual{_TagAD1{T}, T, 1}

_TagAD2{T} = Autodiff.ForwardDiff.Tag{Autodiff.JSMDDiffTag, _TimeNodeFunAD1{T}}
_TimeNodeFunAD2{T} = Autodiff.ForwardDiff.Dual{_TagAD2{T}, _TimeNodeFunAD1{T}, 1}

const TimeNodeWrappers = FunctionWrappersWrapper

function _time_node_wrapper(::Type{T}, fun) where {T}
    argtypes = (
        Tuple{T},
        Tuple{_TimeNodeFunAD1{T}},
        Tuple{_TimeNodeFunAD2{T}},
    )
    rettypes = (T, _TimeNodeFunAD1{T}, _TimeNodeFunAD2{T})
    return FunctionWrappersWrapper(
        fun, argtypes, rettypes; cache=NoCache(), policy=AllowAll()
    )
end

"""A graph node containing a scale's parent and its directional offset functions."""
struct TimeScaleNode{T,FFP<:TimeNodeWrappers,FTP<:TimeNodeWrappers} <:
       AbstractJSMDGraphNode
    name::Symbol
    id::Int
    parentid::Int
    ffp::FFP
    ftp::FTP
end

get_node_id(scale::TimeScaleNode) = scale.id

function TimeScaleNode{T}(
    name::Symbol,
    id::Int,
    parentid::Int,
    ffp::FFP,
    ftp::FTP,
) where {T,FFP<:TimeNodeWrappers,FTP<:TimeNodeWrappers}
    return TimeScaleNode{T,FFP,FTP}(name, id, parentid, ffp, ftp)
end

function Base.show(io::IO, scale::TimeScaleNode{T}) where {T}
    text = "TimeScaleNode{$T}(name=$(scale.name), id=$(scale.id)"
    scale.parentid == scale.id || (text *= ", parent=$(scale.parentid)")
    return println(io, text * ")")
end

"""
    TimeSystem{T}()

Create an empty directed time-scale graph whose registered offset functions use scalar
type `T`. Custom systems remain graph based and can be prepared for repeated use with
[`prepare_time_conversion`](@ref).
"""
struct TimeSystem{T<:Number,Builtin}
    scales::MappedNodeGraph{TimeScaleNode{T},SimpleDiGraph{Int}}
end

TimeSystem{T}() where {T} = TimeSystem{T,false}(MappedDiGraph(TimeScaleNode{T}))
_default_time_system(::Type{T}) where {T} =
    TimeSystem{T,true}(MappedDiGraph(TimeScaleNode{T}))

"""Register a fully constructed node. This is a low-level interface."""
function add_timescale!(system::TimeSystem{T}, scale::TimeScaleNode{T}) where {T}
    return add_vertex!(system.scales, scale)
end

@inline has_timescale(system::TimeSystem, id::Int) = has_vertex(system.scales, id)
@inline timescales(system::TimeSystem) = system.scales

function _zero_offset(seconds)
    @error "a zero-offset transformation has been applied in the TimeSystem"
    return zero(seconds)
end

"""
    add_timescale!(system, scale, from_parent; parent, ftp)

Register `scale` in `system`. `from_parent` returns the offset from `parent` to `scale`.
The optional reverse offset is supplied as `ftp`. Omitting it creates a one-way scale.
"""
function add_timescale!(
    system::TimeSystem{T},
    scale::AbstractTimeScale,
    ffp::Function=_zero_offset;
    ftp=nothing,
    parent=nothing,
) where {T}
    name = timescale_name(scale)
    id = timescale_id(scale)
    isnothing(id) && throw(ArgumentError("the time scale has no registered numeric ID"))
    parent_id = isnothing(parent) ? nothing : timescale_alias(parent)

    if has_timescale(system, id)
        throw(ArgumentError("TimeScale with id $id is already registered in the given TimeSystem"))
    end

    if isnothing(parent)
        if !isempty(timescales(system))
            throw(ArgumentError(
                "a parent timescale is required because the given TimeSystem already " *
                "contains a root timescale.",
            ))
        end
        parent_id = id
    elseif isnothing(parent_id) || !has_timescale(system, parent_id)
        throw(ArgumentError(
            "the specified parent timescale with ID $parent_id is not registered in " *
            "the given TimeSystem",
        ))
    end

    node = TimeScaleNode{T}(
        name,
        id,
        parent_id,
        _time_node_wrapper(T, ffp),
        _time_node_wrapper(T, isnothing(ftp) ? _zero_offset : ftp),
    )
    add_timescale!(system, node)

    if !isnothing(parent)
        add_edge!(timescales(system), parent_id, id)
        isnothing(ftp) || add_edge!(timescales(system), id, parent_id)
    end
    return nothing
end
