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
