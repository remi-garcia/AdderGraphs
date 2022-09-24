# Getters
function get_value(addernode::AdderNode)
    return addernode.value
end


"""



"""
function get_input_edges(addernode::AdderNode)
    return addernode.inputs
end


# Extract more information
"""



"""
function get_input_addernodes(addernode::AdderNode)
    return get_input_addernode.(get_input_edges(addernode))
end


function get_input_addernode_values(addernode::AdderNode)
    return get_value.(get_input_addernode.(get_input_edges(addernode)))
end


function get_input_shifts(addernode::AdderNode)
    return get_input_shift.(get_input_edges(addernode))
end


function are_negative_inputs(addernode::AdderNode)
    return is_negative_input.(get_input_edges(addernode))
end


function get_truncations(addernode::AdderNode)
    return get_truncation.(get_input_edges(addernode))
end


function compute_nb_onebit_adders(addernode::AdderNode, wordlength_in::Int)
    inputs_signed = are_negative_inputs(addernode)
    inputs_shifts = get_input_shifts(addernode)
    inputs_truncations = get_truncations(addernode)
    inputs_wl = get_input_wordlengths(addernode, wordlength_in)
    @assert length(inputs_signed) == 2
    @assert length(inputs_shifts) == 2
    current_wl = get_adder_wordlength(addernode, wordlength_in)
    return current_wl - min(0, minimum(inputs_shifts)) - ((current_wl > maximum(inputs_wl + inputs_shifts) ? 1 : 0) + max(inputs_signed[2] ? 0 : inputs_truncations[1] + inputs_shifts[1], inputs_signed[1] ? 0 : inputs_truncations[2] + inputs_shifts[2]))
end


function get_adder_wordlength(addernode::AdderNode, wordlength_in::Int) #TODO take truncations/errors into account
    return round(Int, log2(get_value(addernode) * (2^wordlength_in - 1)), RoundUp)
end

function get_input_wordlengths(addernode::AdderNode, wordlength_in::Int) #TODO take truncations/errors into account
    return get_adder_wordlength.(get_input_addernodes(addernode), wordlength_in)
end

function get_input_depths(addernode::AdderNode)
    return get_depth.(get_input_addernodes(addernode))
end

function set_truncations!(addernode::AdderNode, truncations::Vector{Int})
    input_edges = get_input_edges(addernode)
    @assert length(truncations)==length(input_edges)
    for i in 1:length(input_edges)
        set_truncation!(input_edges[i], truncations[i])
    end
    return addernode
end


# Generation
function produce_addernode(input_adders::Vector{AdderNode}, shifts::Vector{Int}, sign_switch::Vector{Bool})
    @assert length(input_values) == length(shifts)
    @assert length(shifts) == length(sign_switch)
    inputs = [InputEdge(input_values[i], shifts[i], sign_switch[i]) for i in 1:length(sign_switch)]
    addernode = AdderNode(_compute_value_from_inputs(inputs), inputs)
    return addernode
end



function get_depth(addernode::AdderNode)::Int
    if get_value(addernode) == 1
        return 0
    end
    if addernode.stage == 0
        return maximum(get_depth.(get_input_addernodes(addernode)).+1)
    end
    return addernode.stage
end


function set_stage!(addernode::AdderNode, stage::Int)
    addernode.stage = stage
    return addernode
end


function evaluate_node(addernode::AdderNode, input_values::Vector{Int}; wlIn::Int, apply_truncations::Bool=true, verbose::Bool=false)
    shifts = get_input_shifts(addernode)
    negative_inputs = are_negative_inputs(addernode)
    truncations = get_truncations(addernode)
    if !apply_truncations
        return round(Int, sum((-1)^(negative_inputs[i])*2.0^(shifts[i])*input_values[i] for i in 1:length(input_values)))
    end
    if minimum(shifts) >= 0
        output_value = sum((-1)^(negative_inputs[i])*(2^(shifts[i])*input_values[i] &
            max(2^(round(Int, log2(get_value(addernode)), RoundUp)+wlIn+1)-1 -
                (truncations[i]+shifts[i]-1 >= 0 ? sum(2^j for j in 0:(truncations[i]+shifts[i]-1)) : 0), 0))
                    for i in 1:length(input_values))
    else
        #TODO in general case
        output_value = round(Int, sum((-1)^(negative_inputs[i])*(input_values[i] &
            max(2^(round(Int, log2(get_value(addernode)), RoundUp)+wlIn+1)-1 -
                (truncations[i]+shifts[i]-1 >= 0 ? sum(2^j for j in 0:(truncations[i]+shifts[i]-1)) : 0), 0))
                    for i in 1:length(input_values))*2.0^(shifts[1]))
    end
    return output_value
end

function same_adders(addernode1::AdderNode, addernode2::AdderNode)
    return ((get_value(addernode1) == get_value(addernode2)) && (get_depth(addernode1) == get_depth(addernode2)))
end

function get_nb_registers(addernode::AdderNode, addergraph::AdderGraph)
    depth_addernode = get_depth(addernode)
    if get_value(addernode) in odd.(abs.(get_outputs(addergraph)))
        is_used_as_output = true
        current_depth = get_depth(addernode)
        current_value = get_value(addernode)
        for other_addernode in get_nodes(addergraph)
            if get_value(other_addernode) == current_value
                if get_depth(other_addernode) > current_depth
                    is_used_as_output = false
                end
            end
        end
        if is_used_as_output
            return max(0, get_adder_depth(addergraph)-depth_addernode)+1-same_adders(addernode, get_origin(addergraph))
        end
    end
    nb_registers = 0
    for other_addernode in get_nodes(addergraph)
        if same_adders(addernode, get_input_addernodes(other_addernode)[1]) || same_adders(addernode, get_input_addernodes(other_addernode)[2])
            nb_registers = max(nb_registers, get_depth(other_addernode)-(depth_addernode+1))
        end
    end
    if !same_adders(addernode, get_origin(addergraph))
        nb_registers =+ 1
    end
    return nb_registers
end

function get_nb_register_bits(addernode::AdderNode, wordlength_in::Int, addergraph::AdderGraph)
    nb_registers = get_nb_registers(addernode, addergraph)
    nb_bits = get_adder_wordlength(addernode, wordlength_in)
    return nb_registers*nb_bits
end
