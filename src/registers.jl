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


function get_nb_registers(addergraph::AdderGraph)
    total_nb_registers = get_nb_registers(get_origin(addergraph), addergraph)
    for addernode in get_nodes(addergraph)
        total_nb_registers += get_nb_registers(addernode, addergraph)
    end
    return total_nb_registers
end


function get_nb_register_bits(addergraph::AdderGraph, wordlength_in::Int)
    total_nb_register_bits = get_nb_register_bits(get_origin(addergraph), wordlength_in, addergraph)
    for addernode in get_nodes(addergraph)
        total_nb_register_bits += get_nb_register_bits(addernode, wordlength_in, addergraph)
    end
    return total_nb_register_bits
end
