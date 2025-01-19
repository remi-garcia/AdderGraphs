function signal_naming(addernode::AdderNode)
    signal_input_left = "x_iL_$(get_value(addernode))_$(get_depth(addernode))"
    signal_input_right = "x_iR_$(get_value(addernode))_$(get_depth(addernode))"
    signal_output = "x_O_$(get_value(addernode))_$(get_depth(addernode))"
    return (signal_input_left, signal_input_right, signal_output)
end

function signal_naming(dsp_value::Int)
    variable_output = "x_O_$(dsp_value)"
    return variable_output
end

function signal_wl(addernode::AdderNode, wordlength_in::Int)
    addernode_wl = get_adder_wordlength(addernode, wordlength_in)
    input_wls = get_input_wordlengths(addernode, wordlength_in)
    @assert length(input_wls) == 2
    signal_input_left = input_wls[1]
    signal_input_right = input_wls[2]
    signal_output = addernode_wl
    return (signal_input_left, signal_input_right, signal_output)
end

function output_naming_vhdl(output_value::Int)
    return "o$(output_value < 0 ? "minus" : "")$(abs(output_value))"
end

function signal_output_naming(output_value::Int)
    return "x_$(output_naming_vhdl(output_value))"
end

function entity_naming(addernode::AdderNode)
    return "Addernode_$(get_value(addernode))_$(get_depth(addernode))"
end

function entity_naming(addergraph::AdderGraph)
    entity_name = "Addergraph_$(join(output_naming_vhdl.(get_outputs(addergraph)), "_"))"
    if length(entity_name) >= 40
        entity_name = strip(entity_name[1:min(length(entity_name),40)], '_')*"_etc"
    end
    return entity_name
end

function entity_naming(outputs::Vector{Int})
    entity_name = "Outputs_$(join(output_naming_vhdl.(outputs), "_"))"
    if length(entity_name) >= 40
        entity_name = strip(entity_name[1:min(length(entity_name),40)], '_')*"_etc"
    end
    return entity_name
end

function ct_entity_naming(output_value::Int)
    entity_name = "ct_$(output_naming_vhdl(output_value))"
    return entity_name
end


function adder_port_names()
    return ("i_L", "i_R", "o_SUM")
end
