module AdderGraphs

abstract type AbstractInputEdge end

# OriginAdder: AdderNode(1, Vector{InputEdge}(), 0, 0, -1.0, 0)
mutable struct AdderNode
    value::Int
    inputs::Vector{AbstractInputEdge}
    stage::Int
end

mutable struct InputEdge <: AbstractInputEdge
    input_adder::AdderNode
    shift::Int
    is_negative::Bool
    truncation::Int
end

function InputEdge(input_adder::AdderNode, shift::Int, is_negative::Bool)
    return InputEdge(input_adder, shift, is_negative, 0)
end

function AdderNode(value::Int, inputs::Vector{InputEdge})
    addernode = AdderNode(value, inputs, 0)
    set_stage!(addernode, get_depth(addernode))
    return addernode
end

function origin_addernode()
    return AdderNode(1, Vector{InputEdge}())
end

mutable struct AdderGraph
    origin::AdderNode
    constants::Vector{AdderNode}
    outputs::Vector{Int}
end

function AdderGraph(c::Vector{AdderNode}, v::Vector{Int})
    return AdderGraph(origin_addernode(), c, v)
end
function AdderGraph()
    return AdderGraph(Vector{AdderNode}(), Vector{Int}())
end
function AdderGraph(v::Vector{Int})
    return AdderGraph(Vector{AdderNode}(), v)
end
function AdderGraph(c::Vector{AdderNode})
    return AdderGraph(c, Vector{Int}())
end


export AdderGraph
export AdderNode
export InputEdge


include("utils.jl")
include("inputedge.jl")
include("truncations_errors.jl")
include("registers.jl")
include("addernode.jl")
include("addergraph.jl")
include("vhdl.jl")
include("hls.jl")

# Utils
export odd


# InputEdge
export get_input_addernode
export get_input_shift
export is_negative_input
export get_input_addernode_value
export get_truncation
export set_truncation!


# AdderGraph
export length
export isempty
export get_nodes
export push_node!
export push_output!
export get_outputs
export get_origin
export compute_total_nb_onebit_adders
export compute_all_nb_onebit_adders
export get_addernodes_by_value
export read_addergraph
export write_addergraph
export isvalid
export evaluate
export get_maximal_output_errors
export pretty_print_get_maximal_output_errors
export get_maximal_errors
export read_addergraph_truncations
export write_addergraph_truncations
export get_adder_depth
export get_nb_registers
export get_nb_register_bits
export get_error_bounds
export get_maximal_output_error_bound

# AdderNode
export get_value
export get_input_edges
export get_input_addernodes
export get_input_addernode_values
export get_input_shifts
export are_negative_inputs
export get_truncations
export set_truncations!
export produce_addernode
export get_depth
export set_stage!
export get_adder_wordlength
export get_input_wordlengths
export get_input_depths

# VHDL
export vhdl_addergraph_generation
export write_vhdl

# HLS
export hls_addergraph_generation
export write_hls

end # module
