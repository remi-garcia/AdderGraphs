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
    return current_wl - min(0, minimum(inputs_shifts)) - ((current_wl > maximum(inputs_wl .+ inputs_shifts) ? 1 : 0) + max(inputs_signed[2] ? 0 : inputs_truncations[1] + inputs_shifts[1], inputs_signed[1] ? 0 : inputs_truncations[2] + inputs_shifts[2]))
end


function get_adder_wordlength(addernode::AdderNode, wordlength_in::Int)
    return round(Int, log2(get_value(addernode) * (2^wordlength_in - 1) + maximum(abs.(adder_value_bounds_zeros(addernode)[1]))), RoundUp)
end

function get_input_wordlengths(addernode::AdderNode, wordlength_in::Int)
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
    if addernode.stage != 0
        return addernode.stage
    end
    if addernode.stage == 0
        if get_value(addernode) != 1 || length(get_input_edges(addernode)) != 0
            set_stage!(addernode, maximum(get_depth.(get_input_addernodes(addernode)).+1))
        end
    end
    return addernode.stage
end


function set_stage!(addernode::AdderNode, stage::Int)
    addernode.stage = stage
    return addernode
end


function adder_value_bounds_zeros(addernode::AdderNode, delta_bounds::Vector{Tuple{Int, Int}}, input_zeros::Vector{Int}; verbose::Bool=false)
    shifts = get_input_shifts(addernode)
    for i in 1:length(shifts)
        delta_bounds[i] = (round(Int, delta_bounds[i][1]*2.0^shifts[i], RoundDown), round(Int, delta_bounds[i][2]*2.0^shifts[i], RoundUp))
    end
    negative_inputs = are_negative_inputs(addernode)
    for i in 1:length(negative_inputs)
        if negative_inputs[i]
            delta_bounds[i] = (delta_bounds[i][2], delta_bounds[i][1])
        end
    end
    truncations = get_truncations(addernode)
    for i in 1:length(truncations)
        delta_bounds[i] = (
            delta_bounds[i][1] + max(2^truncations[i]-2^input_zeros[i], 0),
            delta_bounds[i][2]
        )
    end

    output_bounds = (sum(delta_bounds[i][1] for i in 1:length(delta_bounds)), sum(delta_bounds[i][2] for i in 1:length(delta_bounds)))

    output_zeros = minimum(max.(shifts .+ truncations, input_zeros))

    return output_bounds, output_zeros
end


function adder_value_bounds_zeros(addernode::AdderNode; verbose::Bool=false,
        all_delta_bounds::Dict{Tuple{Int, Int}, Tuple{Int, Int}}=Dict{Tuple{Int, Int}, Tuple{Int, Int}}((1, 0) => (0, 0)),
        all_input_zeros::Dict{Tuple{Int, Int}, Int}=Dict{Tuple{Int, Int}, Int}((1, 0) => 0)
    )::Tuple{Tuple{Int, Int}, Int}
    dict_key = (get_value(addernode), get_depth(addernode))
    if haskey(all_delta_bounds, dict_key) && haskey(all_input_zeros, dict_key)
        return all_delta_bounds[dict_key], all_input_zeros[dict_key]
    end
    delta_bounds = Vector{Tuple{Int, Int}}()
    input_zeros = Vector{Int}()
    for current_input in get_input_addernodes(addernode)
        current_delta, current_zero = adder_value_bounds_zeros(current_input, verbose=verbose, all_delta_bounds=all_delta_bounds, all_input_zeros=all_input_zeros)
        push!(delta_bounds, current_delta)
        push!(input_zeros, current_zero)
    end
    shifts = get_input_shifts(addernode)
    for i in 1:length(shifts)
        delta_bounds[i] = (round(Int, delta_bounds[i][1]*2.0^shifts[i], RoundDown), round(Int, delta_bounds[i][2]*2.0^shifts[i], RoundUp))
    end
    negative_inputs = are_negative_inputs(addernode)
    for i in 1:length(negative_inputs)
        if negative_inputs[i]
            delta_bounds[i] = (delta_bounds[i][2], delta_bounds[i][1])
        end
    end
    truncations = get_truncations(addernode)
    for i in 1:length(truncations)
        delta_bounds[i] = (
            delta_bounds[i][1] + max(2^truncations[i]-2^input_zeros[i], 0),
            delta_bounds[i][2]
        )
    end

    output_bounds = (sum(delta_bounds[i][1] for i in 1:length(delta_bounds)), sum(delta_bounds[i][2] for i in 1:length(delta_bounds)))
    output_zeros = minimum(max.(shifts .+ truncations, input_zeros))
    all_delta_bounds[dict_key] = output_bounds
    all_input_zeros[dict_key] = output_zeros

    return output_bounds, output_zeros
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
