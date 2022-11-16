import Base.length
import Base.isempty
import Base.isvalid

function length(addergraph::AdderGraph)
    return length(addergraph.constants)
end

function isempty(addergraph::AdderGraph)
    return (length(addergraph.constants)+length(addergraph.outputs)==0)
end

function get_nodes(addergraph::AdderGraph)
    return addergraph.constants
end

function push_node!(addergraph::AdderGraph, addernode::AdderNode)
    push!(addergraph.constants, addernode)
    return addergraph
end

function push_node!(addergraph::AdderGraph, inputs::Vector{InputEdge})
    push_node!(addergraph, AdderNode(_compute_value_from_inputs(inputs), inputs))
end

function push_output!(addergraph::AdderGraph, output_value::Int)
    push!(addergraph.outputs, output_value)
    return addergraph
end

function get_outputs(addergraph::AdderGraph)
    return addergraph.outputs
end

function get_origin(addergraph::AdderGraph)
    return addergraph.origin
end


function compute_total_nb_onebit_adders(addergraph::AdderGraph, wordlength_in::Int)::Int
    total_nb_onebit_adders = 0
    for addernode in get_nodes(addergraph)
        total_nb_onebit_adders += compute_nb_onebit_adders(addernode, wordlength_in)
    end
    return total_nb_onebit_adders
end


function compute_all_nb_onebit_adders(addergraph::AdderGraph, wordlength_in::Int)::Dict{Tuple{Int, Int}, Int}
    all_nb_onebit_adders = Dict{Tuple{Int, Int}, Int}()
    for addernode in get_nodes(addergraph)
        all_nb_onebit_adders[(get_value(addernode), get_depth(addernode))] = compute_nb_onebit_adders(addernode, wordlength_in)
    end
    return all_nb_onebit_adders
end


function get_addernodes_by_value(addergraph::AdderGraph, value::Int)
    addernodes = Vector{AdderNode}()
    if get_value(get_origin(addergraph)) == value
        push!(addernodes, get_origin(addergraph))
    end
    for addernode in get_nodes(addergraph)
        if get_value(addernode) == value
            push!(addernodes, addernode)
        end
    end
    return addernodes
end


function read_addergraph(s::String)
    addergraph = AdderGraph()
    adders_registers_outputs = split(s[3:(end-2)], "},{")
    for val in adders_registers_outputs
        if startswith(val, "'A'")
            node_details = split(val, ",")
            node_value = parse(Int, node_details[2][2:(end-1)])
            node_stage = parse(Int, node_details[3])
            node_inputs_signed = Vector{Int}()
            node_input_stages = Vector{Int}()
            node_input_shifts = Vector{Int}()
            for current_input in 1:div(length(node_details)-3, 3)
                push!(node_inputs_signed, parse(Int, node_details[3*current_input+1][2:(end-1)]))
                push!(node_input_stages, parse(Int, node_details[3*current_input+2]))
                push!(node_input_shifts, parse(Int, node_details[3*current_input+3]))
            end
            node_inputs = Vector{Int}(abs.(node_inputs_signed))
            node_subtraction = Vector{Bool}(abs.(div.(sign.(node_inputs_signed).-1, 2)))
            addernode_inputs = Vector{AdderNode}()
            for i in 1:length(node_subtraction)
                possible_addernodes = get_addernodes_by_value(addergraph, node_inputs[i])
                possible_depths = get_depth.(possible_addernodes)
                target_depth = node_input_stages[i]
                if !(target_depth in possible_depths)
                    target_depth = maximum(filter!(x->x<target_depth, possible_depths))
                end
                for possible_addernode in possible_addernodes
                    if get_depth(possible_addernode) == target_depth
                        push!(addernode_inputs, possible_addernode)
                    end
                end
            end
            push_node!(addergraph,
                AdderNode(
                    node_value,
                    [InputEdge(addernode_inputs[i], node_input_shifts[i], node_subtraction[i]) for i in 1:length(node_subtraction)],
                    node_stage
                )
            )
        elseif startswith(val, "'O'")
            push_output!(addergraph, parse(Int, split(val, ",")[2][2:(end-1)]))
        end
    end
    return addergraph
end


function write_addergraph(addergraph::AdderGraph; pipeline::Bool=false, flopoco_format::Bool=true)
    adderstring = ""
    if flopoco_format
        adderstring *= "graph=\"{"
    else
        adderstring *= "{"
    end
    if isempty(addergraph)
        return adderstring*"}"
    end
    maximum_depth = maximum(get_depth.(get_nodes(addergraph)))
    use_depth_by_value = Dict{Int, Vector{Int}}([val => Vector{Int}() for val in get_value.(get_nodes(addergraph))])
    use_depth_by_value[1] = Vector{Int}()
    if pipeline
        if 1 in odd.(abs.(get_outputs(addergraph)))
            push!(use_depth_by_value[1], maximum_depth)
        end
        for addernode in get_nodes(addergraph)
            if odd(abs(get_value(addernode))) in odd.(abs.(get_outputs(addergraph)))
                push!(use_depth_by_value[get_value(addernode)], maximum_depth)
            end
            for input_edge in get_input_edges(addernode)
                push!(use_depth_by_value[get_input_addernode_value(input_edge)], get_depth(addernode)-1)
            end
        end
        for addernode in get_nodes(addergraph)
            unique!(use_depth_by_value[get_value(addernode)])
            sort!(use_depth_by_value[get_value(addernode)], rev=true)
        end
        unique!(use_depth_by_value[1])
        sort!(use_depth_by_value[1], rev=true)
        need_register = Dict{Int, Vector{Int}}([val => collect((use_depth_by_value[val][end]-1):(use_depth_by_value[val][1])) for val in keys(use_depth_by_value)])
        for val in keys(need_register)
            this_value_depths = sort(get_depth.(get_addernodes_by_value(addergraph, val)))
            for adderdepth in this_value_depths
                deletepos = findfirst(isequal(adderdepth), need_register[val])
                if deletepos !== nothing
                    deleteat!(need_register[val], deletepos)
                end
                current_depth = adderdepth-1
                while !isempty(need_register[val]) && current_depth >= need_register[val][1] && !(current_depth in use_depth_by_value[val])
                    deletepos = findfirst(isequal(current_depth), need_register[val])
                    if deletepos !== nothing
                        deleteat!(need_register[val], deletepos)
                    end
                    current_depth -= 1
                end
            end
        end
    end
    output_values = Vector{Int}()
    firstcoefnocomma = true
    coefficients = get_outputs(addergraph)
    for coefind in 1:length(coefficients)
        coef = coefficients[coefind]
        if coef != 0
            value = odd(abs(coef))
            if !(abs(coef) in output_values)
                push!(output_values, abs(coef))
                shift = round(Int, log2(abs(coef)/value))
                if !firstcoefnocomma
                    adderstring *= ","
                else
                    firstcoefnocomma = false
                end
                if !pipeline
                    adderstring *= "{'O',[$(abs(coef))],$(maximum_depth),[$(value)],$(maximum(get_depth.(get_addernodes_by_value(addergraph, value)))),$(shift)}"
                else
                    adderstring *= "{'O',[$(abs(coef))],$(maximum_depth),[$(value)],$(maximum_depth),$(shift)}"
                end
            end
        end
    end
    if pipeline
        for val in keys(need_register)
            for current_depth in need_register[val]
                adderstring *= ",{'R',[$val],$(current_depth),[$val],$(current_depth-1)}"
            end
        end
    end
    for addernode in get_nodes(addergraph)
        adderstring *= ",{'A',[$(get_value(addernode))],$(get_depth(addernode))"
        for input_edge in get_input_edges(addernode)
            adderstring *= ",[$((-1)^(is_negative_input(input_edge))*get_input_addernode_value(input_edge))],"
            if !pipeline
                adderstring *= "$(get_depth(get_input_addernode(input_edge))),$(get_input_shift(input_edge))"
            else
                adderstring *= "$(get_depth(addernode)-1),$(get_input_shift(input_edge))"
            end
        end
        adderstring *= "}"
    end
    adderstring *= "}"
    if flopoco_format
        adderstring *= "\""
    end
    return adderstring
end


function isvalid(addergraph::AdderGraph)
    addernodes = get_nodes(addergraph)
    node_values = get_value.(addernodes)
    for output in get_outputs(addergraph)
        if !(output in node_values)
            return false
        end
    end
    for addernode in addernodes
        left_value, right_value = get_input_addernode_values(addernode)
        left_shift, right_shift = get_input_shifts(addernode)
        left_neg, right_neg = are_negative_inputs(addernode)
        if left_neg
            left_value = -left_value
        end
        if right_neg
            right_value = -right_value
        end
        if get_value(addernode) != left_value*(2.0^left_shift)+right_value*(2.0^right_shift)
            return false
        end
    end
    return true
end


function _evaluate(addergraph::AdderGraph, input_value::Int; wlIn::Int, apply_internal_truncations::Bool=true, verbose::Bool=false)::Tuple{Dict{Int, Int}, Dict{Int, Int}}
    # if !apply_truncations
    #     return input_value*get_outputs(addergraph)
    # end
    nodes_value = Dict{Int, Int}([1=>input_value])
    for addernode in get_nodes(addergraph)
        nodes_value[get_value(addernode)] = evaluate_node(addernode, [nodes_value[get_input_addernode_values(addernode)[i]] for i in 1:length(get_input_addernodes(addernode))], wlIn=wlIn, apply_truncations=apply_internal_truncations, verbose=verbose)
    end
    output_values = Dict{Int, Int}([output_value => nodes_value[odd(abs(output_value))]*2^(log2odd(abs(output_value))) for output_value in get_outputs(addergraph)])
    return (nodes_value, output_values)
end


function evaluate(args...; kwargs...)::Dict{Int, Int}
    return _evaluate(args...; kwargs...)[2]
end


function evaluate_adders(args...; kwargs...)::Dict{Int, Int}
    return _evaluate(args...; kwargs...)[1]
end


function get_adders_wordlengths(addergraph::AdderGraph, wordlength_in::Int)::Dict{Int, Int}
    all_wordlengths = Dict{Int, Int}()
    for addernode in get_nodes(addergraph)
        all_wordlengths[get_value(addernode)] = get_adder_wordlength(addernode, wordlength_in)
    end
    return all_wordlengths
end


function get_adder_depth(addergraph::AdderGraph)
    adderdepth = 0
    outputs = odd.(abs.(get_outputs(addergraph)))
    for addernode in get_nodes(addergraph)
        if get_value(addernode) in outputs
            if get_depth(addernode) > adderdepth
                adderdepth = get_depth(addernode)
            end
        end
    end
    return adderdepth
end


function get_output_addernode(addergraph::AdderGraph, output_value::Int)
    addernode = get_origin(addergraph)
    for current_addernode in get_nodes(addergraph)
        if get_value(current_addernode) == odd(abs(output_value))
            if get_depth(current_addernode) > get_depth(addernode)
                addernode = current_addernode
            end
        end
    end
    return addernode
end
