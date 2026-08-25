"""
    AbstractTimeScale

Supertype of all time-scale singleton types.
"""
abstract type AbstractTimeScale end

"""Return the numeric ID associated with a time scale."""
timescale_id(::AbstractTimeScale) = nothing

"""Return the display name associated with a time scale."""
timescale_name(::AbstractTimeScale) = nothing

"""Return the graph ID associated with a time scale or integer ID."""
@inline timescale_alias(scale::AbstractTimeScale) = timescale_id(scale)
@inline timescale_alias(id::Int) = id

"""
    @timescale(name, id[, type])

Define a singleton time scale named `name` with graph ID `id`. If `type` is omitted,
the concrete type name is formed by appending `TimeScale` to `name`.

# Examples
```julia
@timescale NTS 100 NewTimeScale
timescale_id(NTS) == 100
```
"""
macro timescale(name::Symbol, id::Int, type::Union{Symbol,Nothing}=nothing)
    type = isnothing(type) ? Symbol(name, :TimeScale) : type
    type = Symbol(format_camelcase(Symbol, String(type)))
    type_str = String(type)
    name_split = join(split(type_str, r"(?=[A-Z])"), " ")
    name_str = String(name)

    scaleid_expr = :(@inline Tempo.timescale_id(::$type) = $id)
    name_expr = :(@inline Tempo.timescale_name(::$type) = Symbol($name_str))
    show_expr = :(Base.show(io::IO, ::$type) = print(io, "$($(name_str))"))

    return quote
        """
            $($type_str) <: AbstractTimeScale

        A type representing the $($name_split) ($($name_str)) time scale.
        """
        struct $type <: AbstractTimeScale end

        """Singleton instance representing the $($name_split) ($($name_str)) time scale."""
        const $(esc(name)) = $(esc(type))()

        $(esc(scaleid_expr))
        $(esc(name_expr))
        $(esc(show_expr))
        nothing
    end
end
