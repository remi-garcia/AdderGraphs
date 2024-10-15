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


function adder_generation_hls(
        addernode::AdderNode, addergraph::AdderGraph;
        wordlength_in::Int,
        verbose::Bool=false,
        function_name::String="",
        adder_function_name_prefix::String="",
        adder_function_name_suffix::String="",
        twos_complement::Bool=true,
        kwargs...
    )
    var_names = adder_variable_names()
    if isempty(function_name)
        function_name = function_naming(addernode)
    end
    function_name = "$(adder_function_name_prefix)$(isempty(adder_function_name_prefix) ? "" : "_")$(function_name)$(isempty(adder_function_name_suffix) ? "" : "_")$(adder_function_name_suffix)"
    hls_str = ""

    addernode_value = get_value(addernode)
    input_values = get_input_addernode_values(addernode)
    @assert length(input_values) == 2
    addernode_depth = get_depth(addernode)
    addernode_wl = get_adder_wordlength(addernode, wordlength_in)
    input_wls = get_input_wordlengths(addernode, wordlength_in)
    input_shifts = get_input_shifts(addernode)
    input_signs = are_negative_inputs(addernode) # true is negative
    input_depths = get_input_depths(addernode)
    if minimum(input_shifts) < 0
        @assert input_shifts[1] == input_shifts[2]
    end

    # function
    hls_str *= """
    // Generation of addernode $(addernode_value)
    // from inputs $(input_values[1]) and $(input_values[2])
    """

    hls_str *= "ap_$(twos_complement ? "" : "u")int<$(addernode_wl)> $(function_name)(ap_$(twos_complement ? "" : "u")int<$(input_wls[1])> $(var_names[1]), ap_$(twos_complement ? "" : "u")int<$(input_wls[2])> $(var_names[2])) {\n"
    hls_str *= "\t#pragma HLS inline\n"

    # Function
    hls_str *= "\tap_$(twos_complement ? "" : "u")int<$(addernode_wl)> $(var_names[3]);\n"
    variable_output_name = "x_out_c$(addernode_value)"
    hls_str *= "\tap_$(twos_complement ? "" : "u")int<$(addernode_wl-min(0, input_shifts[1]))> $(variable_output_name);\n"

    # Left
    variable_left_name = "x_in_left_c$(input_values[1])"
    variable_left_wl = input_wls[1]
    variable_left_shifted_name = "$(variable_left_name)_shifted"
    variable_left_shifted_wl = input_wls[1]+max(0, input_shifts[1])
    hls_str *= "\tap_$(twos_complement ? "" : "u")int<$(variable_left_wl)> $(variable_left_name);\n"
    if input_shifts[1] > 0
        hls_str *= "\tap_$(twos_complement ? "" : "u")int<$(variable_left_shifted_wl)> $(variable_left_shifted_name);\n"
    else
        variable_left_shifted_name = variable_left_name
    end

    # Right
    variable_right_name = "x_in_right_c$(input_values[2])"
    variable_right_wl = input_wls[2]
    variable_right_shifted_name = "$(variable_right_name)_shifted"
    variable_right_shifted_wl = input_wls[2]+max(0, input_shifts[2])
    hls_str *= "\tap_$(twos_complement ? "" : "u")int<$(variable_right_wl)> $(variable_right_name);\n"
    if input_shifts[2] > 0
        hls_str *= "\tap_$(twos_complement ? "" : "u")int<$(variable_right_shifted_wl)> $(variable_right_shifted_name);\n"
    else
        variable_right_shifted_name = variable_right_name
    end

    hls_str *= "\n"
    hls_str *= "\t$(variable_left_name) = $(var_names[1]);\n"
    hls_str *= "\t$(variable_right_name) = $(var_names[2]);\n"

    # Resize for shifts
    if input_shifts[1] > 0
        hls_str *= "\t$(variable_left_shifted_name) = $(variable_left_name) << $(input_shifts[1]);\n"
    end
    if input_shifts[2] > 0
        hls_str *= "\t$(variable_right_shifted_name) = $(variable_right_name) << $(input_shifts[2]);\n"
    end

    hls_str *= "\t$(variable_output_name) = "
    hls_str *= "$(input_signs[1] ? "-" : "")"
    hls_str *= "$(variable_left_shifted_name)"
    hls_str *= " $(input_signs[2] ? "-" : "+") "
    hls_str *= "$(variable_right_shifted_name);\n"

    hls_str *= "\t$(var_names[3]) = $(variable_output_name)$(minimum(input_shifts) < 0 ? " >> $(abs(input_shifts[1]))" : "");\n"

    hls_str *= "\treturn $(var_names[3]);\n"
    hls_str *= "}\n"

    return (function_name, hls_str)
end




function hls_addergraph_generation(
        addergraph::AdderGraph;
        wordlength_in::Int,
        verbose::Bool=false,
        addergraph_function_name::String="",
        addergraph_function_name_prefix::String="",
        addergraph_function_name_suffix::String="",
        adder_function_name::String="",
        twos_complement::Bool=true,
        kwargs...
    )
    addergraph_function_name = "$(addergraph_function_name_prefix)$(isempty(addergraph_function_name_prefix) ? "" : "_")$(addergraph_function_name)$(isempty(addergraph_function_name_suffix) ? "" : "_")$(addergraph_function_name_suffix)"
    output_values = unique(get_outputs(addergraph))

    hls_str = "#include \"ap_int.h\"\n\n"
    adder_ports = Dict{AdderNode, String}()
    current_adder = 1
    for addernode in get_nodes(addergraph)
        current_adder_function_name = ""
        if !isempty(adder_function_name)
            current_adder_function_name = "$(adder_function_name)_$(current_adder)"
            current_adder += 1
        end
        current_adder_function_name, adder_hls_str = adder_generation_hls(addernode, addergraph; wordlength_in=wordlength_in, function_name=current_adder_function_name, twos_complement=twos_complement, kwargs...)
        hls_str *= adder_hls_str
        hls_str *= "\n\n\n"
        adder_ports[addernode] = current_adder_function_name
    end

    if isempty(addergraph_function_name)
        addergraph_function_name = function_naming(addergraph_function_name)
    end

    # Function
    hls_str *= """
    // Generation of addergraph
    """

    variable_input_name = "x"
    hls_str *= "void $(addergraph_function_name)(ap_$(twos_complement ? "" : "u")int<$(wordlength_in)> $(variable_input_name)"
    for output_value in output_values
        if output_value == 0
            continue
        end
        output_name = output_naming_hls(output_value)
        shift = round(Int, log2(abs(output_value)/odd(abs(output_value))))
        wl_adder_dsp = 0
        if !done_with_dsp(addergraph, output_value)
            addernode = get_output_addernode(addergraph, output_value)
            wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in)
        else
            dsp_value = get_output_dsp(addergraph, output_value)
            wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in)
        end
        hls_str *= ", ap_$(twos_complement ? "" : "u")int<$(wl_adder_dsp+shift)> &$(output_name)"
    end
    hls_str *= ") {\n"

    variable_input_wl = wordlength_in

    addernode = get_origin(addergraph)
    _, _, variable_output_name = variable_naming(addernode)
    variable_output_wl = variable_input_wl
    hls_str *= "\tap_$(twos_complement ? "" : "u")int<$(variable_output_wl)> $(variable_output_name);\n"
    for addernode in get_nodes(addergraph)
        variable_left_name, variable_right_name, variable_output_name = variable_naming(addernode)
        variable_left_wl, variable_right_wl, variable_output_wl = variable_wl(addernode, wordlength_in)
        hls_str *= "\tap_$(twos_complement ? "" : "u")int<$(variable_output_wl)> $(variable_output_name);\n"
    end
    for output_value in output_values
        if output_value == 0
            continue
        end        
        output_name = variable_output_naming(output_value)
        shift = round(Int, log2(abs(output_value)/odd(abs(output_value))))
        wl_adder_dsp = 0
        if !done_with_dsp(addergraph, output_value)
            addernode = get_output_addernode(addergraph, output_value)
            wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in)
        else
            dsp_value = get_output_dsp(addergraph, output_value)
            wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in)
        end
        hls_str *= "\tap_$(twos_complement ? "" : "u")int<$(wl_adder_dsp+shift)> $(output_name);\n"
    end

    hls_str *= "\n"

    addernode = get_origin(addergraph)
    _, _, variable_output_name = variable_naming(addernode)
    hls_str *= "\t$(variable_output_name) = $(variable_input_name);\n"

    for addernode in get_nodes(addergraph)
        variable_left_name, variable_right_name, variable_output_name = variable_naming(addernode)
        left_input, right_input = get_input_addernodes(addernode)
        _, _, variable_left_output_name = variable_naming(left_input)
        _, _, variable_right_output_name = variable_naming(right_input)
        # hls_str *= "\t$(variable_left_name) = $(variable_left_output_name);\n"
        # hls_str *= "\t$(variable_right_name) = $(variable_right_output_name);\n"
        # hls_str *= "\t$(variable_output_name) = $(function_naming(addernode))($(variable_left_name), $(variable_right_name));\n"
        hls_str *= "\t$(variable_output_name) = $(adder_ports[addernode])($(variable_left_output_name), $(variable_right_output_name));\n"
    end

    for dsp_value in get_dsp(addergraph)
        variable_output_name = variable_naming(dsp_value)
        hls_str *= "\t#pragma HLS bind_op variable=$(variable_output_name) op=mul impl=dsp latency=0\n"
        hls_str *= "\t$(variable_output_name) = $(dsp_value)*$(variable_input_name);\n"
    end

    for output_value in output_values
        if output_value == 0
            continue
        end
        wl_adder_dsp = 0
        variable_output_name = ""
        if !done_with_dsp(addergraph, output_value)
            addernode = get_output_addernode(addergraph, output_value)
            _, _, variable_output_name = variable_naming(addernode)
        else
            dsp_value = get_output_dsp(addergraph, output_value)
            variable_output_name = variable_naming(dsp_value)
        end
        output_name = variable_output_naming(output_value)
        shift = round(Int, log2(abs(output_value)/odd(abs(output_value))))
        hls_str *= "\t$(output_name) = $(variable_output_name)$(shift > 0 ? " << $(shift)" : "");\n"
        ag_output_name = output_naming_hls(output_value)
        hls_str *= "\t$(ag_output_name) = $(output_value < 0 ? "-" : "")$(output_name);\n"
    end

    hls_str *= "}\n"

    return addergraph_function_name, hls_str
end


function write_hls(
        addergraph::AdderGraph;
        hls_filename::String="addergraph.cpp",
        verbose::Bool=false,
        kwargs...
    )
    hls_str = ""
    _, hls_str = hls_addergraph_generation(addergraph; verbose=verbose, kwargs...)
    open(hls_filename, "w") do writefile
        write(writefile, hls_str)
    end
    return nothing
end