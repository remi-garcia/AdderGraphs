function variable_naming(addernode::AdderNode)
    variable_input_left = "x_iL_$(get_value(addernode))"
    variable_input_right = "x_iR_$(get_value(addernode))"
    variable_output = "x_O_$(get_value(addernode))"
    return (variable_input_left, variable_input_right, variable_output)
end

function variable_naming(dsp_value::Int)
    variable_output = "x_O_$(dsp_value)"
    return variable_output
end

function variable_wl(addernode::AdderNode, wordlength_in::Int)
    addernode_wl = get_adder_wordlength(addernode, wordlength_in)
    input_wls = get_input_wordlengths(addernode, wordlength_in)
    @assert length(input_wls) == 2
    variable_input_left = input_wls[1]
    variable_input_right = input_wls[2]
    variable_output = addernode_wl
    return (variable_input_left, variable_input_right, variable_output)
end

function output_naming_hls(output_value::Int)
    return "o$(output_value < 0 ? "minus" : "")$(abs(output_value))"
end

function variable_output_naming(output_value::Int)
    return "x_$(output_naming_hls(output_value))"
end

function function_naming(addernode::AdderNode)
    return "Addernode_$(get_value(addernode))"
end

function function_naming(addergraph::AdderGraph)
    function_name = "Addergraph_$(join(output_naming_hls.(get_outputs(addergraph)), "_"))"
    if length(function_name) >= 40
        function_name = strip(function_name[1:min(length(function_name),40)], '_')*"_etc"
    end
    return function_name
end

function function_naming(outputs::Vector{Int})
    function_name = "Outputs_$(join(output_naming_hls.(outputs), "_"))"
    if length(function_name) >= 40
        function_name = strip(function_name[1:min(length(function_name),40)], '_')*"_etc"
    end
    return function_name
end

function adder_variable_names()
    return ("i_L", "i_R", "o_SUM")
end
