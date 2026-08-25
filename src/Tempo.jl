module Tempo

using FunctionWrappersWrappers: FunctionWrappersWrapper, AllowAll, NoCache
using FunctionWrappers: FunctionWrapper

using JSMDInterfaces.Errors: AbstractGenericException, @custom_error

using JSMDInterfaces.Graph: 
    AbstractJSMDGraphNode, 
    add_edge!,
    add_vertex!, 
    get_path,
    has_vertex

using JSMDUtils: format_camelcase
import JSMDUtils.Autodiff

using PrecompileTools: PrecompileTools

using SMDGraphs:
    MappedNodeGraph,
    MappedDiGraph,
    SimpleDiGraph,
    get_mappednode

import SMDGraphs: get_node_id

export DJ2000, DMJD, DJM0

include("constants.jl")
include("errors.jl")
include("convert.jl")
include("parse.jl")
include("leapseconds.jl")
include("offset.jl")

include("scales.jl")
include("system.jl")
include("conversion.jl")
include("builtins.jl")

export TIMESCALES, @timescale, add_timescale!, prepare_time_conversion,
       PreparedTimeConversion, TimeSystem, timescale_alias, timescale_name, timescale_id

export Date, Time,
       year, month, day, find_dayinyear,
       j2000, j2000s,j2000c, hour, minute, second, DateTime

include("datetime.jl")
include("origin.jl")

export Duration, value

include("duration.jl")

export Epoch, j2000, j2000s, j2000c, doy, timescale, value

include("epoch.jl")

# Package precompilation routines
include("precompile.jl")

end
