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

function adder_port_names()
    return ("i_L", "i_R", "o_SUM")
end


function adder_generation_vhdl(
        addernode::AdderNode, addergraph::AdderGraph;
        wordlength_in::Int,
        target_frequency::Int=400,
        verbose::Bool=false,
        entity_name::String="",
        apply_truncations::Bool=true,
        twos_complement::Bool=true,
        kwargs...
    )
    port_names = adder_port_names()
    if isempty(entity_name)
        entity_name = entity_naming(addernode)
    end
    vhdl_str = """
    --------------------------------------------------------------------------------
    --                      $(entity_name)
    -- VHDL generated for Kintex7 @ $(target_frequency)MHz
    -- Authors: Rémi Garcia
    --------------------------------------------------------------------------------
    -- Target frequency (MHz): $(target_frequency)
    -- Input signals: $(port_names[1]) $(port_names[2])
    -- Output signals: $(port_names[3])

    library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    library std;
    """

    addernode_value = get_value(addernode)
    input_values = get_input_addernode_values(addernode)
    @assert length(input_values) == 2
    addernode_depth = get_depth(addernode)
    addernode_wl = get_adder_wordlength(addernode, wordlength_in)
    input_wls = get_input_wordlengths(addernode, wordlength_in)
    input_shifts = get_input_shifts(addernode)
    input_truncations = get_truncations(addernode)
    input_signs = are_negative_inputs(addernode) # true is negative
    input_depths = get_input_depths(addernode)
    if minimum(input_shifts) < 0
        @assert input_shifts[1] == input_shifts[2]
    end

    inputsum_max_wl = max(input_wls[1]+max(0,input_shifts[1]), input_wls[2]+max(0,input_shifts[2]))
    # println(inputsum_max_wl)
    # println("$(input_values[1]) -- $(input_wls[1]) -- $(input_shifts[1])")
    # println("$(input_values[2]) -- $(input_wls[2]) -- $(input_shifts[2])")
    if !(true in input_signs)
        if minimum(input_shifts) >= 0
            if inputsum_max_wl < addernode_wl
                inputsum_max_wl += 1
                @assert inputsum_max_wl == addernode_wl
            # else
            #     inputsum_max_wl = inputsum_max_wl
            end
        # else
        #     inputsum_max_wl = inputsum_max_wl
        end
    # else
    #     inputsum_max_wl = inputsum_max_wl
    end
    if minimum(input_shifts) < 0
        inputsum_max_wl = max(inputsum_max_wl, addernode_wl + abs(input_shifts[1]))
    end

    # Entity
    vhdl_str *= """
    -- Generation of addernode $(addernode_value) at depth $(addernode_depth)
    -- from inputs $(input_values[1]) and $(input_values[2]) at depths
    -- $(input_depths[1]) and $(input_depths[2])
    """

    vhdl_str *= """
    entity $(entity_name) is
    """

    port_str = "port (\n"
    # vhdl_str *= "\t\tclk : in std_logic;"
    # vhdl_str *= " -- Clock\n"
    port_str *= "\t\t$(port_names[1]) : in std_logic_vector($(input_wls[1]-1) downto 0);"
    port_str *= " -- Left input\n"
    port_str *= "\t\t$(port_names[2]) : in std_logic_vector($(input_wls[2]-1) downto 0);"
    port_str *= " -- Right input\n"
    port_str *= "\t\t$(port_names[3]) : out std_logic_vector($(addernode_wl-1) downto 0)"
    port_str *= " -- Output sum\n"
    port_str *= "\t);"
    vhdl_str *= "\t$(port_str)\n"
    vhdl_str *= "end entity;\n"
    vhdl_str *= "\n"

    # Architecture
    vhdl_str *= """
    architecture arch of $(entity_name) is
    """

    signal_output_name = "x_out_c$(addernode_value)"
    signal_output_wl_adjusted_name = "$(signal_output_name)_adjusted"
    vhdl_str *= "signal $(signal_output_name) : std_logic_vector($(addernode_wl-1) downto 0);"
    vhdl_str *= " -- Output signal\n"
    vhdl_str *= "signal $(signal_output_wl_adjusted_name) : std_logic_vector($(inputsum_max_wl-1) downto 0);"
    vhdl_str *= " -- Output signal with adjusted wordlength\n"

    # Left
    signal_left_name = "x_in_left_c$(input_values[1])"
    signal_left_wl = input_wls[1]
    signal_left_shifted_name = "$(signal_left_name)_shifted"
    signal_left_shifted_wl = input_wls[1]+max(0, input_shifts[1])
    signal_left_wl_adjusted_name = "$(signal_left_name)_adjusted"
    signal_left_wl_adjusted_wl = inputsum_max_wl
    vhdl_str *= "signal $(signal_left_name) : std_logic_vector($(signal_left_wl-1) downto 0);"
    vhdl_str *= " -- Input left signal\n"
    if input_shifts[1] > 0
        vhdl_str *= "signal $(signal_left_shifted_name) : std_logic_vector($(signal_left_shifted_wl-1) downto 0);"
        vhdl_str *= " -- Input left signal with shift\n"
    else
        signal_left_shifted_name = signal_left_name
    end
    if signal_left_shifted_wl != signal_left_wl_adjusted_wl
        vhdl_str *= "signal $(signal_left_wl_adjusted_name) : std_logic_vector($(signal_left_wl_adjusted_wl-1) downto 0);"
        vhdl_str *= " -- Input left signal with adjusted wordlength\n"
    else
        signal_left_wl_adjusted_name = signal_left_shifted_name
    end

    # Right
    signal_right_name = "x_in_right_c$(input_values[2])"
    signal_right_wl = input_wls[2]
    signal_right_shifted_name = "$(signal_right_name)_shifted"
    signal_right_shifted_wl = input_wls[2]+max(0, input_shifts[2])
    signal_right_wl_adjusted_name = "$(signal_right_name)_adjusted"
    signal_right_wl_adjusted_wl = inputsum_max_wl
    vhdl_str *= "signal $(signal_right_name) : std_logic_vector($(signal_right_wl-1) downto 0);"
    vhdl_str *= " -- Input right signal\n"
    if input_shifts[2] > 0
        vhdl_str *= "signal $(signal_right_shifted_name) : std_logic_vector($(signal_right_shifted_wl-1) downto 0);"
        vhdl_str *= " -- Input right signal with shift\n"
    else
        signal_right_shifted_name = signal_right_name
    end
    if signal_right_shifted_wl != signal_right_wl_adjusted_wl
        vhdl_str *= "signal $(signal_right_wl_adjusted_name) : std_logic_vector($(signal_right_wl_adjusted_wl-1) downto 0);"
        vhdl_str *= " -- Input right signal with adjusted wordlength\n"
    else
        signal_right_wl_adjusted_name = signal_right_shifted_name
    end

    vhdl_str *= "\nbegin\n"
    if apply_truncations
        if input_truncations[1] != 0
            vhdl_str *= "\t$(signal_left_name) <= $(port_names[1])($(input_wls[1]-1) downto $(input_truncations[1])) & \"$(repeat("0", input_truncations[1]))\";\n"
        else
            vhdl_str *= "\t$(signal_left_name) <= $(port_names[1]);\n"
        end
        if input_truncations[2] != 0
            vhdl_str *= "\t$(signal_right_name) <= $(port_names[2])($(input_wls[2]-1) downto $(input_truncations[2])) & \"$(repeat("0", input_truncations[2]))\";\n"
        else
            vhdl_str *= "\t$(signal_right_name) <= $(port_names[2]);\n"
        end
    else
        vhdl_str *= "\t$(signal_left_name) <= $(port_names[1]);\n"
        vhdl_str *= "\t$(signal_right_name) <= $(port_names[2]);\n"
    end

    # Resize for shifts
    if input_shifts[1] > 0
        vhdl_str *= "\t$(signal_left_shifted_name) <= $(signal_left_name)($(signal_left_wl-1) downto 0) & \"$(repeat("0", input_shifts[1]))\";\n"
    end
    if input_shifts[2] > 0
        vhdl_str *= "\t$(signal_right_shifted_name) <= $(signal_right_name)($(signal_right_wl-1) downto 0) & \"$(repeat("0", input_shifts[2]))\";\n"
    end

    if twos_complement
        if signal_left_shifted_wl != signal_left_wl_adjusted_wl
            vhdl_str *= "\t$(signal_left_wl_adjusted_name) <= "
            vhdl_str *= "($(signal_left_wl_adjusted_wl-signal_left_shifted_wl-1) downto 0 => $(signal_left_shifted_name)($(signal_left_shifted_wl-1))) "
            vhdl_str *= "& $(signal_left_shifted_name)($(signal_left_shifted_wl-1) downto 0);\n"
        end
        if signal_right_shifted_wl != signal_right_wl_adjusted_wl
            vhdl_str *= "\t$(signal_right_wl_adjusted_name) <= "
            vhdl_str *= "($(signal_right_wl_adjusted_wl-signal_right_shifted_wl-1) downto 0 => $(signal_right_shifted_name)($(signal_right_shifted_wl-1))) "
            vhdl_str *= "& $(signal_right_shifted_name)($(signal_right_shifted_wl-1) downto 0);\n"
        end
    else
        if signal_left_shifted_wl != signal_left_wl_adjusted_wl
            vhdl_str *= "\t$(signal_left_wl_adjusted_name) <= "
            vhdl_str *= "\"$(repeat("0", signal_left_wl_adjusted_wl-signal_left_shifted_wl))\" "
            vhdl_str *= "& $(signal_left_shifted_name)($(signal_left_shifted_wl-1) downto 0);\n"
        end
        if signal_right_shifted_wl != signal_right_wl_adjusted_wl
            vhdl_str *= "\t$(signal_right_wl_adjusted_name) <= "
            vhdl_str *= "\"$(repeat("0", signal_right_wl_adjusted_wl-signal_right_shifted_wl))\" "
            vhdl_str *= "& $(signal_right_shifted_name)($(signal_right_shifted_wl-1) downto 0);\n"
        end
    end

    vhdl_str *= "\t$(signal_output_wl_adjusted_name) <= "
    vhdl_str *= "std_logic_vector("
    vhdl_str *= "$(input_signs[1] ? "-" : "")"
    vhdl_str *= "$(twos_complement ? "" : "un")signed($(signal_left_wl_adjusted_name))"
    vhdl_str *= " $(input_signs[2] ? "-" : "+") "
    vhdl_str *= "$(twos_complement ? "" : "un")signed($(signal_right_wl_adjusted_name)));\n"

    if minimum(input_shifts) < 0
        vhdl_str *= "\t$(signal_output_name) <= "
        vhdl_str *= "$(signal_output_wl_adjusted_name)($(addernode_wl+abs(input_shifts[1])-1) downto $(abs(input_shifts[1])))"
        vhdl_str *= ";\n"
    else
        vhdl_str *= "\t$(signal_output_name) <= "
        vhdl_str *= "$(signal_output_wl_adjusted_name)($(addernode_wl-1) downto 0)"
        vhdl_str *= ";\n"
    end
    vhdl_str *= "\t$(port_names[3]) <= $(signal_output_name);\n"
    vhdl_str *= "end architecture;\n"

    return (entity_name, port_str, vhdl_str)
end


function vhdl_addergraph_generation(
        addergraph::AdderGraph;
        wordlength_in::Int, pipeline::Bool=false,
        pipeline_inout::Bool=false,
        with_clk::Bool=true,
        target_frequency::Int=400,
        verbose::Bool=false,
        entity_name::String="",
        adder_entity_name::String="",
        twos_complement::Bool=true,
        kwargs...
    )
    if pipeline || pipeline_inout
        with_clk = true
    end
    if get_adder_depth(addergraph) <= 1
        verbose && pipeline && println("WARNING: Pipeline not necessary for AD=$(get_adder_depth(addergraph))")
        pipeline = false
    end
    output_values = unique(get_outputs(addergraph))
    oddabs_output_values = unique(odd.(abs.(output_values)))

    vhdl_str = ""
    adder_ports = Dict{String, String}()
    current_adder = 1
    for addernode in get_nodes(addergraph)
        current_adder_entity_name = ""
        if !isempty(adder_entity_name)
            current_adder_entity_name = "$(adder_entity_name)_$(current_adder)"
            current_adder += 1
        end
        current_adder_entity_name, adder_port_str, adder_vhdl_str = adder_generation_vhdl(addernode, addergraph; wordlength_in=wordlength_in, target_frequency=target_frequency, entity_name=current_adder_entity_name, kwargs...)
        adder_ports[current_adder_entity_name] = adder_port_str
        vhdl_str *= adder_vhdl_str
        vhdl_str *= "\n\n\n"
    end

    if isempty(entity_name)
        entity_name = entity_naming(addergraph)
    end
    vhdl_str *= """
    --------------------------------------------------------------------------------
    --                      $(entity_name)
    -- VHDL generated for Kintex7 @ $(target_frequency)MHz
    -- Authors: Rémi Garcia
    --------------------------------------------------------------------------------
    -- Target frequency (MHz): $(target_frequency)
    -- Input signals: $(with_clk ? "clk " : "")input_x
    -- Output signals: $(join([output_naming_vhdl(output_value) for output_value in output_values], " "))

    library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    library std;
    """

    # Entity
    vhdl_str *= """
    -- Generation of addergraph
    """

    vhdl_str *= "entity $(entity_name) is\n"
    port_str = "port (\n"
    # vhdl_str *= "\t\tclk : in std_logic;"
    # vhdl_str *= " -- Clock\n"

    # Always provide input clock for correct power results with flopoco script
    # if pipeline
    if with_clk
        port_str *= "\t\tclk : in std_logic;"
        port_str *= " -- Clock\n"
    end
    # end
    port_str *= "\t\tinput_x : in std_logic_vector($(wordlength_in-1) downto 0);"
    port_str *= " -- Input\n"
    if length(output_values) >= 2
        for output_value in output_values[1:(end-1)]
            output_name = output_naming_vhdl(output_value)
            shift = round(Int, log2(abs(output_value)/odd(abs(output_value))))
            wl_adder_dsp = 0
            if !done_with_dsp(addergraph, output_value)
                addernode = get_output_addernode(addergraph, output_value)
                wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in)
            else
                dsp_value = get_output_dsp(addergraph, output_value)
                wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in)
            end
            port_str *= "\t\t$(output_name) : out std_logic_vector($(wl_adder_dsp+shift-1) downto 0);"
            port_str *= " -- Output $(output_value)\n"
        end
    end
    output_value = output_values[end]
    output_name = output_naming_vhdl(output_value)
    shift = round(Int, log2(abs(output_value)/odd(abs(output_value))))
    wl_adder_dsp = 0
    if !done_with_dsp(addergraph, output_value)
        addernode = get_output_addernode(addergraph, output_value)
        wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in)
    else
        dsp_value = get_output_dsp(addergraph, output_value)
        wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in)
    end
    port_str *= "\t\t$(output_name) : out std_logic_vector($(wl_adder_dsp+shift-1) downto 0)"
    port_str *= " -- Output $(output_value)\n"
    port_str *= "\t);\n"

    vhdl_str *= port_str
    vhdl_str *= "end entity;\n"
    vhdl_str *= "\n"

    # Architecture
    vhdl_str *= """
    architecture arch of $(entity_name) is
    """
    for adder_entity_name in keys(adder_ports)
        vhdl_str *= "\tcomponent $(adder_entity_name) is\n"
        vhdl_str *= "\t\t$(adder_ports[adder_entity_name])\n"
        vhdl_str *= "\tend component;\n\n"
    end

    signal_input_name = "x_in"
    signal_input_wl = wordlength_in
    vhdl_str *= "signal $(signal_input_name) : std_logic_vector($(signal_input_wl-1) downto 0);\n"

    addernode = get_origin(addergraph)
    _, _, signal_output_name = signal_naming(addernode)
    signal_output_wl = signal_input_wl
    vhdl_str *= "signal $(signal_output_name) : std_logic_vector($(signal_output_wl-1) downto 0);\n"
    if pipeline_inout && !pipeline
        vhdl_str *= "signal $(signal_output_name)_$(0)_register : std_logic_vector($(signal_output_wl-1) downto 0);\n"
    end
    for i in 0:(get_nb_registers(addernode, addergraph)-1+1)
        vhdl_str *= "signal $(signal_output_name)_$(i) : std_logic_vector($(signal_output_wl-1) downto 0);\n"
        if pipeline
            if i <= get_adder_depth(addergraph)-1
                vhdl_str *= "signal $(signal_output_name)_$(i)_register : std_logic_vector($(signal_output_wl-1) downto 0);\n"
            end
        end
    end
    if pipeline_inout
        if get_value(addernode) in oddabs_output_values
            vhdl_str *= "signal $(signal_output_name)_$(get_adder_depth(addergraph))_register : std_logic_vector($(signal_output_wl-1) downto 0);\n"
        end
    end
    for addernode in get_nodes(addergraph)
        signal_left_name, signal_right_name, signal_output_name = signal_naming(addernode)
        signal_left_wl, signal_right_wl, signal_output_wl = signal_wl(addernode, wordlength_in)
        vhdl_str *= "signal $(signal_left_name) : std_logic_vector($(signal_left_wl-1) downto 0);\n"
        vhdl_str *= "signal $(signal_right_name) : std_logic_vector($(signal_right_wl-1) downto 0);\n"
        vhdl_str *= "signal $(signal_output_name) : std_logic_vector($(signal_output_wl-1) downto 0);\n"
        for i in get_depth(addernode):get_depth(addernode)+get_nb_registers(addernode, addergraph)-1
            vhdl_str *= "signal $(signal_output_name)_$(i) : std_logic_vector($(signal_output_wl-1) downto 0);\n"
            if pipeline
                if i <= get_adder_depth(addergraph)-1
                    vhdl_str *= "signal $(signal_output_name)_$(i)_register : std_logic_vector($(signal_output_wl-1) downto 0);\n"
                end
            end
        end
        if pipeline_inout
            if get_value(addernode) in oddabs_output_values
                vhdl_str *= "signal $(signal_output_name)_$(get_adder_depth(addergraph))_register : std_logic_vector($(signal_output_wl-1) downto 0);\n"
            end
        end
    end
    for dsp_value in get_dsp(addergraph)
        signal_dsp_name = signal_naming(dsp_value)
        vhdl_str *= "signal $(signal_dsp_name) : std_logic_vector($(get_dsp_wordlength(dsp_value, wordlength_in)-1) downto 0);\n"
        vhdl_str *= "signal $(signal_dsp_name)_$(get_adder_depth(addergraph)) : std_logic_vector($(get_dsp_wordlength(dsp_value, wordlength_in)-1) downto 0);\n"
        if pipeline || pipeline_inout
            vhdl_str *= "signal $(signal_dsp_name)_$(get_adder_depth(addergraph))_register : std_logic_vector($(get_dsp_wordlength(dsp_value, wordlength_in)-1) downto 0);\n"
        end
    end
    for output_value in output_values
        output_name = signal_output_naming(output_value)
        shift = round(Int, log2(abs(output_value)/odd(abs(output_value))))
        wl_adder_dsp = 0
        if !done_with_dsp(addergraph, output_value)
            addernode = get_output_addernode(addergraph, output_value)
            wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in)
        else
            dsp_value = get_output_dsp(addergraph, output_value)
            wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in)
        end
        vhdl_str *= "signal $(output_name) : std_logic_vector($(wl_adder_dsp+shift-1) downto 0);\n"
    end
    if !isempty(get_dsp(addergraph))
        vhdl_str *= "attribute use_dsp : string;\n"
    end
    for dsp_value in get_dsp(addergraph)
        vhdl_str *= "attribute use_dsp of $(signal_naming(dsp_value)) : signal is \"yes\";\n"
    end

    vhdl_str *= "\nbegin\n"
    vhdl_str *= "\t$(signal_input_name) <= input_x;\n"

    addernode = get_origin(addergraph)
    _, _, signal_output_name = signal_naming(addernode)
    vhdl_str *= "\t$(signal_output_name) <= $(signal_input_name);\n"

    # https://stackoverflow.com/questions/9989913/vhdl-how-to-use-clk-and-reset-in-process
    # https://vhdlguru.blogspot.com/2011/01/what-is-pipelining-explanation-with.html
    if pipeline
        # Register to signals at clk
        vhdl_str *= "\t-- Add registers for pipelining\n"
        vhdl_str *= "\tprocess(clk)\n"
        vhdl_str *= "\tbegin\n"
        vhdl_str *= "\t\tif(rising_edge(clk)) then\n"
        for i in 0:(get_adder_depth(addergraph)-1)
            vhdl_str *= "\t\t\t-- Stage $(i)\n"
            addernode = get_origin(addergraph)
            _, _, signal_output_name = signal_naming(addernode)
            if i >= get_depth(addernode)
                if i <= min(get_depth(addernode)+get_nb_registers(addernode, addergraph), get_adder_depth(addergraph)-1)
                    vhdl_str *= "\t\t\t$(signal_output_name)_$(i) <= $(signal_output_name)_$(i)_register;\n"
                end
            end
            for addernode in get_nodes(addergraph)
                _, _, signal_output_name = signal_naming(addernode)
                if get_depth(addernode) != get_adder_depth(addergraph)
                    if i >= get_depth(addernode)
                        if i <= min(get_depth(addernode)+get_nb_registers(addernode, addergraph)-1, get_adder_depth(addergraph)-1)
                            vhdl_str *= "\t\t\t$(signal_output_name)_$(i) <= $(signal_output_name)_$(i)_register;\n"
                        end
                    end
                # else
                #     # No registers
                end
            end
        end
        if pipeline_inout
            vhdl_str *= "\t\t\t-- Stage $(get_adder_depth(addergraph))\n"
            addernode = get_origin(addergraph)
            _, _, signal_output_name = signal_naming(addernode)
            if get_value(addernode) in oddabs_output_values
                vhdl_str *= "\t\t\t$(signal_output_name)_$(get_adder_depth(addergraph)) <= $(signal_output_name)_$(get_adder_depth(addergraph))_register;\n"
            end
            for addernode in get_nodes(addergraph)
                _, _, signal_output_name = signal_naming(addernode)
                if get_value(addernode) in oddabs_output_values
                    vhdl_str *= "\t\t\t$(signal_output_name)_$(get_adder_depth(addergraph)) <= $(signal_output_name)_$(get_adder_depth(addergraph))_register;\n"
                end
            end
        end
        if !isempty(get_dsp(addergraph))
            vhdl_str *= "\t\t\t-- DSP\n"
            for dsp_value in get_dsp(addergraph)
                signal_dsp_name = signal_naming(dsp_value)
                vhdl_str *= "\t\t\t$(signal_dsp_name)_$(get_adder_depth(addergraph)) <= $(signal_dsp_name)_$(get_adder_depth(addergraph))_register;\n"
            end
        end
        vhdl_str *= "\t\tend if;\n"
        vhdl_str *= "\tend process;\n"
        # Signal to register
        addernode = get_origin(addergraph)
        _, _, signal_output_name = signal_naming(addernode)
        vhdl_str *= "\t$(signal_output_name)_$(get_depth(addernode))_register <= $(signal_output_name);\n"
        for i in (get_depth(addernode)+1):(get_depth(addernode)+get_nb_registers(addernode, addergraph)-1+1)
            if pipeline_inout || i != get_adder_depth(addergraph)
                vhdl_str *= "\t$(signal_output_name)_$(i)_register <= $(signal_output_name)_$(i-1);\n"
            else
                vhdl_str *= "\t$(signal_output_name)_$(i) <= $(signal_output_name)_$(i-1);\n"
            end
        end

        for addernode in get_nodes(addergraph)
            _, _, signal_output_name = signal_naming(addernode)
            if get_depth(addernode) != get_adder_depth(addergraph)
                vhdl_str *= "\t$(signal_output_name)_$(get_depth(addernode))_register <= $(signal_output_name);\n"
                for i in (get_depth(addernode)+1):(get_depth(addernode)+get_nb_registers(addernode, addergraph)-1)
                    if pipeline_inout || i != get_adder_depth(addergraph)
                        vhdl_str *= "\t$(signal_output_name)_$(i)_register <= $(signal_output_name)_$(i-1);\n"
                    else
                        vhdl_str *= "\t$(signal_output_name)_$(i) <= $(signal_output_name)_$(i-1);\n"
                    end
                end
            else
                if pipeline_inout
                    vhdl_str *= "\t$(signal_output_name)_$(get_depth(addernode))_register <= $(signal_output_name);\n"
                else
                    vhdl_str *= "\t$(signal_output_name)_$(get_depth(addernode)) <= $(signal_output_name);\n"
                end
            end
        end
        for dsp_value in get_dsp(addergraph)
            signal_dsp_name = signal_naming(dsp_value)
            vhdl_str *= "\t$(signal_dsp_name)_$(get_adder_depth(addergraph))_register <= $(signal_dsp_name);\n"
        end
    elseif pipeline_inout
        # Register to signals at clk
        vhdl_str *= "\t-- Add registers\n"
        vhdl_str *= "\tprocess(clk)\n"
        vhdl_str *= "\tbegin\n"
        vhdl_str *= "\t\tif(rising_edge(clk)) then\n"
        vhdl_str *= "\t\t\t-- Input;\n"
        addernode = get_origin(addergraph)
        _, _, signal_output_name = signal_naming(addernode)
        vhdl_str *= "\t\t\t$(signal_output_name)_$(0) <= $(signal_output_name)_$(0)_register;\n"
        vhdl_str *= "\t\t\t-- Outputs AG;\n"
        if get_value(addernode) in oddabs_output_values
            vhdl_str *= "\t\t\t$(signal_output_name)_$(get_adder_depth(addergraph)) <= $(signal_output_name)_$(get_adder_depth(addergraph))_register;\n"
        end
        for addernode in get_nodes(addergraph)
            if get_value(addernode) in oddabs_output_values
                _, _, signal_output_name = signal_naming(addernode)
                vhdl_str *= "\t\t\t$(signal_output_name)_$(get_adder_depth(addergraph)) <= $(signal_output_name)_$(get_adder_depth(addergraph))_register;\n"
            end
        end
        if !isempty(get_dsp(addergraph))
            vhdl_str *= "\t\t\t-- Outputs DSP\n"
            for dsp_value in get_dsp(addergraph)
                signal_dsp_name = signal_naming(dsp_value)
                vhdl_str *= "\t\t\t$(signal_dsp_name)_$(get_adder_depth(addergraph)) <= $(signal_dsp_name)_$(get_adder_depth(addergraph))_register;\n"
            end
        end
        vhdl_str *= "\t\tend if;\n"
        vhdl_str *= "\tend process;\n"
        # Signal to register
        addernode = get_origin(addergraph)
        _, _, signal_output_name = signal_naming(addernode)
        vhdl_str *= "\t$(signal_output_name)_$(get_depth(addernode))_register <= $(signal_output_name);\n"
        for i in (get_depth(addernode)+1):(get_depth(addernode)+get_nb_registers(addernode, addergraph)-1+1)
            if i == get_adder_depth(addergraph)
                vhdl_str *= "\t$(signal_output_name)_$(i)_register <= $(signal_output_name)_$(i-1);\n"
            else
                vhdl_str *= "\t$(signal_output_name)_$(i) <= $(signal_output_name)_$(i-1);\n"
            end
        end

        for addernode in get_nodes(addergraph)
            _, _, signal_output_name = signal_naming(addernode)
            if get_depth(addernode) != get_adder_depth(addergraph)
                vhdl_str *= "\t$(signal_output_name)_$(get_depth(addernode)) <= $(signal_output_name);\n"
                for i in (get_depth(addernode)+1):(get_depth(addernode)+get_nb_registers(addernode, addergraph)-1)
                    if i == get_adder_depth(addergraph)
                        vhdl_str *= "\t$(signal_output_name)_$(i)_register <= $(signal_output_name)_$(i-1);\n"
                    else
                        vhdl_str *= "\t$(signal_output_name)_$(i) <= $(signal_output_name)_$(i-1);\n"
                    end
                end
            else
                vhdl_str *= "\t$(signal_output_name)_$(get_depth(addernode))_register <= $(signal_output_name);\n"
            end
        end
        for dsp_value in get_dsp(addergraph)
            signal_dsp_name = signal_naming(dsp_value)
            vhdl_str *= "\t$(signal_dsp_name)_$(get_adder_depth(addergraph))_register <= $(signal_dsp_name);\n"
        end
    else
        addernode = get_origin(addergraph)
        _, _, signal_output_name = signal_naming(addernode)
        vhdl_str *= "\t$(signal_output_name)_$(get_depth(addernode)) <= $(signal_output_name);\n"
        for i in (get_depth(addernode)+1):(get_depth(addernode)+get_nb_registers(addernode, addergraph)-1+1)
            vhdl_str *= "\t$(signal_output_name)_$(i) <= $(signal_output_name)_$(i-1);\n"
        end

        for addernode in get_nodes(addergraph)
            _, _, signal_output_name = signal_naming(addernode)
            vhdl_str *= "\t$(signal_output_name)_$(get_depth(addernode)) <= $(signal_output_name);\n"
            for i in (get_depth(addernode)+1):(get_depth(addernode)+get_nb_registers(addernode, addergraph)-1)
                vhdl_str *= "\t$(signal_output_name)_$(i) <= $(signal_output_name)_$(i-1);\n"
            end
        end

        for dsp_value in get_dsp(addergraph)
            signal_dsp_name = signal_naming(dsp_value)
            vhdl_str *= "\t$(signal_dsp_name)_$(get_adder_depth(addergraph)) <= $(signal_dsp_name);\n"
        end
    end

    label_use_component_adder = "adder"
    label_use_component_adder_ind = 0

    for addernode in get_nodes(addergraph)
        signal_left_name, signal_right_name, signal_output_name = signal_naming(addernode)
        left_input, right_input = get_input_addernodes(addernode)
        _, _, signal_left_output_name = signal_naming(left_input)
        _, _, signal_right_output_name = signal_naming(right_input)
        vhdl_str *= "\t$(signal_left_name) <= $(signal_left_output_name)_$(get_depth(addernode)-1);\n"
        vhdl_str *= "\t$(signal_right_name) <= $(signal_right_output_name)_$(get_depth(addernode)-1);\n"
        label_use_component_adder_ind += 1
        vhdl_str *= "\t$(label_use_component_adder)$(label_use_component_adder_ind): $(entity_naming(addernode))\n"
        port_names = adder_port_names()
        vhdl_str *= "\t\tport map (\n"
        vhdl_str *= "\t\t\t$(port_names[1]) => $(signal_left_name),\n"
        vhdl_str *= "\t\t\t$(port_names[2]) => $(signal_right_name),\n"
        vhdl_str *= "\t\t\t$(port_names[3]) => $(signal_output_name)\n"
        vhdl_str *= "\t\t);\n\n"
    end

    for dsp_value in get_dsp(addergraph)
        signal_dsp_name = signal_naming(dsp_value)
        vhdl_str *= "\t$(signal_dsp_name) <= std_logic_vector(to_$(twos_complement ? "" : "un")signed($(dsp_value)*to_integer($(twos_complement ? "" : "un")signed($(signal_input_name))), $(wl_adder_dsp)));\n"
    end

    for output_value in output_values
        output_name = signal_output_naming(output_value)
        shift = round(Int, log2(abs(output_value)/odd(abs(output_value))))
        wl_adder_dsp = 0
        signal_output_name = ""
        if !done_with_dsp(addergraph, output_value)
            addernode = get_output_addernode(addergraph, output_value)
            _, _, signal_output_name = signal_naming(addernode)
        else
            dsp_value = get_output_dsp(addergraph, output_value)
            signal_output_name = signal_naming(dsp_value)
        end

        vhdl_str *= "\t$(output_name) <= $(signal_output_name)_$(get_adder_depth(addergraph))$(shift >= 1 ? " & \"$(repeat("0", shift))\"" : "");\n"
        ag_output_name = output_naming_vhdl(output_value)
        vhdl_str *= "\t$(ag_output_name) <= $(output_name);\n"
    end
    vhdl_str *= ""

    vhdl_str *= "end architecture;\n"

    return entity_name, vhdl_str, port_str
end




function vhdl_output_products(
        addergraph::AdderGraph;
        wordlength_in::Int,
        pipeline_inout::Bool=false,
        with_clk::Bool=true,
        target_frequency::Int=400,
        force_dsp::Bool=false,
        verbose::Bool=false,
        twos_complement::Bool=true,
        kwargs...
    )
    if pipeline_inout
        with_clk = true
    end
    output_values = unique(get_outputs(addergraph))
    entity_name = "Products_"*entity_naming(output_values)

    vhdl_str = """
    --------------------------------------------------------------------------------
    --                      $(entity_name)
    -- VHDL generated for Kintex7 @ $(target_frequency)MHz
    -- Authors: Rémi Garcia
    --------------------------------------------------------------------------------
    -- Target frequency (MHz): $(target_frequency)
    -- Input signals: $(with_clk ? "clk " : "")input_x
    -- Output signals: $(join([output_naming_vhdl(output_value) for output_value in output_values], " "))

    library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    library std;
    """

    # Entity
    vhdl_str *= """
    -- Generation of output products
    """

    vhdl_str *= """
    entity $(entity_name) is
        port (
    """
    # Always provide input clock for correct power results with flopoco script
    # if pipeline
    if with_clk
        vhdl_str *= "\t\tclk : in std_logic;"
        vhdl_str *= " -- Clock\n"
    end
    # end
    vhdl_str *= "\t\tinput_x : in std_logic_vector($(wordlength_in-1) downto 0);"
    vhdl_str *= " -- Input\n"
    if length(output_values) >= 2
        for output_value in output_values[1:(end-1)]
            output_name = output_naming_vhdl(output_value)
            wl_adder_dsp = 0
            if !done_with_dsp(addergraph, output_value)
                addernode = get_output_addernode(addergraph, output_value)
                wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in)
            else
                dsp_value = get_output_dsp(addergraph, output_value)
                wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in)
            end
            vhdl_str *= "\t\t$(output_name) : out std_logic_vector($(wl_adder_dsp-1) downto 0);"
            vhdl_str *= " -- Output $(output_value)\n"
        end
    end
    output_value = output_values[end]
    output_name = output_naming_vhdl(output_value)
    wl_adder_dsp = 0
    if !done_with_dsp(addergraph, output_value)
        addernode = get_output_addernode(addergraph, output_value)
        wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in)
    else
        dsp_value = get_output_dsp(addergraph, output_value)
        wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in)
    end
    vhdl_str *= "\t\t$(output_name) : out std_logic_vector($(wl_adder_dsp-1) downto 0)"
    vhdl_str *= " -- Output $(output_value)\n"
    vhdl_str *= "\t);\n"
    vhdl_str *= "end entity;\n"
    vhdl_str *= "\n"

    # Architecture
    vhdl_str *= """
    architecture arch of $(entity_name) is
    """

    signal_input_name = "x_in"
    signal_input_wl = wordlength_in
    vhdl_str *= "signal $(signal_input_name) : std_logic_vector($(signal_input_wl-1) downto 0);\n"

    for output_value in output_values
        wl_adder_dsp = 0
        if !done_with_dsp(addergraph, output_value)
            addernode = get_output_addernode(addergraph, output_value)
            wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in)
        else
            dsp_value = get_output_dsp(addergraph, output_value)
            wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in)
        end
        output_name = signal_output_naming(output_value)
        vhdl_str *= "signal $(output_name) : std_logic_vector($(wl_adder_dsp-1) downto 0);\n"
    end

    if force_dsp
        vhdl_str *= "attribute use_dsp : string;\n"
        for output_value in output_values
            output_name = signal_output_naming(output_value)
            vhdl_str *= "attribute use_dsp of $(output_name) : signal is \"yes\";\n"
        end
    end

    vhdl_str *= "\nbegin\n"
    if !pipeline_inout
        vhdl_str *= "\t$(signal_input_name) <= input_x;\n"
        for output_value in output_values
            vhdl_str *= "\t$(output_naming_vhdl(output_value)) <= $(signal_output_naming(output_value));\n"
        end
    else
        # https://stackoverflow.com/questions/9989913/vhdl-how-to-use-clk-and-reset-in-process
        # https://vhdlguru.blogspot.com/2011/01/what-is-pipelining-explanation-with.html
        # Register to signals at clk
        vhdl_str *= "\t-- Add registers\n"
        vhdl_str *= "\tprocess(clk)\n"
        vhdl_str *= "\tbegin\n"
        vhdl_str *= "\t\tif(rising_edge(clk)) then\n"
        vhdl_str *= "\t\t\t$(signal_input_name) <= input_x;\n"
        for output_value in output_values
            vhdl_str *= "\t\t\t$(output_naming_vhdl(output_value)) <= $(signal_output_naming(output_value));\n"
        end
        vhdl_str *= "\t\tend if;\n"
        vhdl_str *= "\tend process;\n"
    end

    for output_value in output_values
        wl_adder_dsp = 0
        if !done_with_dsp(addergraph, output_value)
            addernode = get_output_addernode(addergraph, output_value)
            wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in)
        else
            dsp_value = get_output_dsp(addergraph, output_value)
            wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in)
        end
        vhdl_str *= "\t$(signal_output_naming(output_value)) <= std_logic_vector(to_$(twos_complement ? "" : "un")signed($(output_value)*to_integer($(twos_complement ? "" : "un")signed($signal_input_name)), $(wl_adder_dsp)));\n"
    end

    vhdl_str *= "end architecture;\n"

    return vhdl_str
end


function vhdl_output_tables(
        addergraph::AdderGraph;
        wordlength_in::Int,
        pipeline_inout::Bool=false,
        with_clk::Bool=true,
        target_frequency::Int=400,
        verbose::Bool=false,
        twos_complement::Bool=true,
        kwargs...
    )
    if pipeline_inout
        with_clk = true
    end
    output_values = unique(get_outputs(addergraph))
    entity_name = "Tables_"*entity_naming(output_values)

    vhdl_str = """
    --------------------------------------------------------------------------------
    --                      $(entity_name)
    -- VHDL generated for Kintex7 @ $(target_frequency)MHz
    -- Authors: Rémi Garcia
    --------------------------------------------------------------------------------
    -- Target frequency (MHz): $(target_frequency)
    -- Input signals: $(with_clk ? "clk " : "")input_x
    -- Output signals: $(join([output_naming_vhdl(output_value) for output_value in output_values], " "))

    library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    library std;
    """

    # Entity
    vhdl_str *= """
    -- Generation of output LUTs
    """
    # https://stackoverflow.com/questions/21976749/design-of-a-vhdl-lut-module

    vhdl_str *= """
    entity $(entity_name) is
        port (
    """
    # Always provide input clock for correct power results with flopoco script
    # if pipeline
    if with_clk
        vhdl_str *= "\t\tclk : in std_logic;"
        vhdl_str *= " -- Clock\n"
    end
    # end
    vhdl_str *= "\t\tinput_x : in std_logic_vector($(wordlength_in-1) downto 0);"
    vhdl_str *= " -- Input\n"
    if length(output_values) >= 2
        for output_value in output_values[1:(end-1)]
            output_name = output_naming_vhdl(output_value)
            wl_adder_dsp = 0
            if !done_with_dsp(addergraph, output_value)
                addernode = get_output_addernode(addergraph, output_value)
                wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in)
            else
                dsp_value = get_output_dsp(addergraph, output_value)
                wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in)
            end
            vhdl_str *= "\t\t$(output_name) : out std_logic_vector($(wl_adder_dsp-1) downto 0);"
            vhdl_str *= " -- Output $(output_value)\n"
        end
    end
    output_value = output_values[end]
    output_name = output_naming_vhdl(output_value)
    wl_adder_dsp = 0
    if !done_with_dsp(addergraph, output_value)
        addernode = get_output_addernode(addergraph, output_value)
        wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in)
    else
        dsp_value = get_output_dsp(addergraph, output_value)
        wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in)
    end
    vhdl_str *= "\t\t$(output_name) : out std_logic_vector($(wl_adder_dsp-1) downto 0)"
    vhdl_str *= " -- Output $(output_value)\n"
    vhdl_str *= "\t);\n"
    vhdl_str *= "end entity;\n"
    vhdl_str *= "\n"

    # Architecture
    vhdl_str *= """
    architecture arch of $(entity_name) is
    """

    vhdl_str *= "attribute rom_style : string;\n"
    signal_input_name = "x_in"
    signal_input_wl = wordlength_in
    vhdl_str *= "signal $(signal_input_name) : std_logic_vector($(signal_input_wl-1) downto 0);\n"
    for output_value in output_values
        if output_value < 0 && -output_value in output_values
            continue
        end
        wlout = round(Int, log2((2^(wordlength_in) - 1)*abs(output_value)), RoundUp)
        lut_outputs = Vector{Vector{Bool}}([reverse(digits(abs(output_value)*i, base=2, pad=wlout))[1:wlout] for i in 0:((2^wordlength_in)-1)])
        if twos_complement
            lut_outputs = Vector{Vector{Bool}}([reverse(digits(abs(output_value)*i, base=2, pad=wlout))[1:wlout] for i in ((-2^(wordlength_in-1))):((2^(wordlength_in-1))-1)])
        end
        wl_adder_dsp = 0
        if !done_with_dsp(addergraph, output_value)
            addernode = get_output_addernode(addergraph, output_value)
            wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in)
        else
            dsp_value = get_output_dsp(addergraph, output_value)
            wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in)
        end
        output_name = signal_output_naming(abs(output_value))
        vhdl_str *= """
        \n\ttype lut_$(output_name) is array (natural range $(twos_complement ? -2^(wordlength_in-1) : 0) to $(twos_complement ? 2^(wordlength_in-1)-1 : 2^(wordlength_in)-1)) of std_logic_vector($(wl_adder_dsp-1) downto 0);
        \tsignal bitcount_$(output_name) : lut_$(output_name) := (
        """
        vhdl_str *= "\t\t"
        for i in 1:(2^(wordlength_in)-1)
            vhdl_str *= "\"$(join(Int.(lut_outputs[i])))\", "
            if mod(i, 4) == 0
                vhdl_str *= "\n\t\t"
            end
        end
        vhdl_str *= "\"$(join(Int.(lut_outputs[end])))\"\n"
        vhdl_str *= "\t);\n"
        vhdl_str *= "attribute rom_style of bitcount_$(output_name) : signal is \"distributed\";\n"

        vhdl_str *= "signal $(signal_output_naming(output_value)) : std_logic_vector($(wl_adder_dsp-1) downto 0);\n"
    end

    vhdl_str *= "\nbegin\n"
    if !pipeline_inout
        vhdl_str *= "\t$(signal_input_name) <= input_x;\n"
        for output_value in output_values
            vhdl_str *= "\t$(output_naming_vhdl(output_value)) <= $(signal_output_naming(output_value));\n"
        end
    else
        # https://stackoverflow.com/questions/9989913/vhdl-how-to-use-clk-and-reset-in-process
        # https://vhdlguru.blogspot.com/2011/01/what-is-pipelining-explanation-with.html
        # Register to signals at clk
        vhdl_str *= "\t-- Add registers\n"
        vhdl_str *= "\tprocess(clk)\n"
        vhdl_str *= "\tbegin\n"
        vhdl_str *= "\t\tif(rising_edge(clk)) then\n"
        vhdl_str *= "\t\t\t$(signal_input_name) <= input_x;\n"
        for output_value in output_values
            vhdl_str *= "\t\t\t$(output_naming_vhdl(output_value)) <= $(signal_output_naming(output_value));\n"
        end
        vhdl_str *= "\t\tend if;\n"
        vhdl_str *= "\tend process;\n"
    end

    for output_value in output_values
        output_name = signal_output_naming(abs(output_value))
        vhdl_str *= "\t$(signal_output_naming(output_value)) <= $(output_value < 0 ? "-" : "")bitcount_$(output_name)(TO_INTEGER(signed($(signal_input_name))));\n"
    end

    vhdl_str *= "end architecture;\n"

    return vhdl_str
end




function vhdl_test_generation(
        addergraph::AdderGraph;
        wordlength_in::Int,
        with_clk::Bool=true,
        verbose::Bool=false,
        original_entity_name::String="",
        entity_name::String="",
        inputs_filename::String="test.input",
        outputs_filename::String="test.output",
        kwargs...
    )
    output_values = unique(get_outputs(addergraph))

    vhdl_str = ""
    if isempty(original_entity_name)
        original_entity_name = entity_naming(addergraph)
    end
    if isempty(entity_name)
        entity_name = "TEST_"*original_entity_name
    end
    vhdl_str *= """
    --------------------------------------------------------------------------------
    --                      $(entity_name)
    -- VHDL generated for testing $(original_entity_name)
    -- Authors: Rémi Garcia
    --------------------------------------------------------------------------------
    -- Input signals: $(with_clk ? "clk " : "")input_x
    -- Output signals: $(join([output_naming_vhdl(output_value) for output_value in output_values], " "))

    library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    library std;
    use std.textio.all;
    library work;\n
    """

    # Entity
    vhdl_str *= """
    -- Generation of tests
    """

    vhdl_str *= "entity $(entity_name) is\n"
    vhdl_str *= "end entity;\n"
    vhdl_str *= "\n"

    # Architecture
    vhdl_str *= """
    architecture behavioral of $(entity_name) is
    """
    vhdl_str *= "\tcomponent $(original_entity_name) is\n"

    port_str = "\t\tport (\n"
    # vhdl_str *= "\t\tclk : in std_logic;"
    # vhdl_str *= " -- Clock\n"

    # Always provide input clock for correct power results with flopoco script
    # if pipeline
    if with_clk
        port_str *= "\t\t\tclk : in std_logic;"
        port_str *= " -- Clock\n"
    end
    # end
    port_str *= "\t\t\tinput_x : in std_logic_vector($(wordlength_in-1) downto 0);"
    port_str *= " -- Input\n"
    if length(output_values) >= 2
        for output_value in output_values[1:(end-1)]
            output_name = output_naming_vhdl(output_value)
            shift = round(Int, log2(abs(output_value)/odd(abs(output_value))))
            wl_adder_dsp = 0
            if !done_with_dsp(addergraph, output_value)
                addernode = get_output_addernode(addergraph, output_value)
                wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in)
            else
                dsp_value = get_output_dsp(addergraph, output_value)
                wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in)
            end
            port_str *= "\t\t\t$(output_name) : out std_logic_vector($(wl_adder_dsp+shift-1) downto 0);"
            port_str *= " -- Output $(output_value)\n"
        end
    end
    output_value = output_values[end]
    shift = round(Int, log2(abs(output_value)/odd(abs(output_value))))
    output_name = output_naming_vhdl(output_value)
    wl_adder_dsp = 0
    if !done_with_dsp(addergraph, output_value)
        addernode = get_output_addernode(addergraph, output_value)
        wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in)
    else
        dsp_value = get_output_dsp(addergraph, output_value)
        wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in)
    end
    port_str *= "\t\t\t$(output_name) : out std_logic_vector($(wl_adder_dsp+shift-1) downto 0)"
    port_str *= " -- Output $(output_value)\n"
    port_str *= "\t\t);\n"

    vhdl_str *= port_str
    vhdl_str *= "\tend component;\n\n"

    vhdl_str *= "signal input_x : std_logic_vector($(wordlength_in-1) downto 0);\n"
    for output_value in output_values
        output_name = output_naming_vhdl(output_value)
        shift = round(Int, log2(abs(output_value)/odd(abs(output_value))))
        wl_adder_dsp = 0
        if !done_with_dsp(addergraph, output_value)
            addernode = get_output_addernode(addergraph, output_value)
            wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in)
        else
            dsp_value = get_output_dsp(addergraph, output_value)
            wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in)
        end
        vhdl_str *= "signal $(output_name) : std_logic_vector($(wl_adder_dsp+shift-1) downto 0);\n"
    end

    vhdl_str *= "signal clk : std_logic;\n"
    vhdl_str *= "signal rst : std_logic;\n\n"

    vhdl_str *= "\tfunction testLine(testCounter : integer; expectedOutputS : string(1 to 10000)"
    for output_value in output_values
        output_name = output_naming_vhdl(output_value)
        shift = round(Int, log2(abs(output_value)/odd(abs(output_value))))
        wl_adder_dsp = 0
        if !done_with_dsp(addergraph, output_value)
            addernode = get_output_addernode(addergraph, output_value)
            wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in)
        else
            dsp_value = get_output_dsp(addergraph, output_value)
            wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in)
        end
        vhdl_str *= "; $(output_name) : std_logic_vector($(wl_adder_dsp+shift-1) downto 0)"
    end
    vhdl_str *= ") return boolean is\n"

    vhdl_str *= "\t\tvariable expectedOutput : line;\n"
    vhdl_str *= "\t\tvariable testSuccess : boolean;\n"
    for output_value in output_values
        output_name = output_naming_vhdl(output_value)
        shift = round(Int, log2(abs(output_value)/odd(abs(output_value))))
        wl_adder_dsp = 0
        if !done_with_dsp(addergraph, output_value)
            addernode = get_output_addernode(addergraph, output_value)
            wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in)
        else
            dsp_value = get_output_dsp(addergraph, output_value)
            wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in)
        end
        vhdl_str *= "\t\tvariable testSuccess_$(output_name) : boolean;\n"
        vhdl_str *= "\t\tvariable expected_$(output_name) : bit_vector($(wl_adder_dsp+shift-1) downto 0);\n"
    end

    vhdl_str *= "\tbegin\n"
    vhdl_str *= "\t\twrite(expectedOutput, expectedOutputS);\n\n"
    for output_value in output_values
        output_name = output_naming_vhdl(output_value)
        vhdl_str *= "\t\ttestSuccess_$(output_name) := false;\n"
        vhdl_str *= "\t\tread(expectedOutput, expected_$(output_name));\n"
        vhdl_str *= "\t\tif $(output_name) = to_stdlogicvector(expected_$(output_name)) then\n"
        vhdl_str *= "\t\t\ttestSuccess_$(output_name) := true;\n"
        vhdl_str *= "\t\tend if;\n\n"
    end

    vhdl_str *= "\t\ttestSuccess := true"
    for output_value in output_values
        output_name = output_naming_vhdl(output_value)
        vhdl_str *= " and testSuccess_$(output_name)"
    end
    vhdl_str *= ";\n"
    vhdl_str *= "\t\treturn testSuccess;\n"
    vhdl_str *= "\tend testLine;\n\n"


    vhdl_str *= "begin\n"
    vhdl_str *= """
        -- Ticking clock signal
        process
        begin
            clk <= '0';
            wait for 5 ns;
            clk <= '1';
            wait for 5 ns;
        end process;
    """

    vhdl_str *= "\n\ttest: $(original_entity_name)\n"
    vhdl_str *= "\t\tport map (\n"
    vhdl_str *= "\t\t\tinput_x => input_x"
    if with_clk
        vhdl_str *= ",\n\t\t\tclk => clk"
    end
    for output_value in output_values
        output_name = output_naming_vhdl(output_value)
        vhdl_str *= ",\n\t\t\t$(output_name) => $(output_name)"
    end
    vhdl_str *= "\n\t\t);\n\n"

    vhdl_str *= "\tprocess\n"
    vhdl_str *= "\t\tvariable input : line;\n"
    vhdl_str *= "\t\tfile inputsFile : text open read_mode is in \"$(inputs_filename)\";\n"
    vhdl_str *= "\t\tvariable v_input_x : bit_vector($(wordlength_in-1) downto 0);\n"

    vhdl_str *= """
        begin
            rst <= '1';
            wait for 10 ns;
            rst <= '0';
    """

    vhdl_str *= "\t\twhile not endfile(inputsFile) loop\n"
    vhdl_str *= "\t\t\treadline(inputsFile, input);\n"
    vhdl_str *= "\t\t\tread(input, v_input_x);\n"
    vhdl_str *= "\t\t\tinput_x <= to_stdlogicvector(v_input_x);\n"
    vhdl_str *= "\t\t\twait for 10 ns;\n"
    vhdl_str *= "\t\tend loop;\n"
    vhdl_str *= "\t\twait for $(10*(get_adder_depth(addergraph)+2+1)) ns; -- For pipelining\n"
    vhdl_str *= "\tend process;\n\n"

    vhdl_str *= "\tprocess\n"
    vhdl_str *= "\t\tvariable expectedOutput : line;\n"
    vhdl_str *= "\t\tvariable expectedOutputString : string(1 to 10000);\n"
    vhdl_str *= "\t\tfile outputsFile : text open read_mode is in \"$(outputs_filename)\";\n"
    vhdl_str *= "\t\tvariable testCounter : integer := 0;\n"
    vhdl_str *= "\t\tvariable errorCounter : integer := 0;\n"
    vhdl_str *= "\t\tvariable testSuccess : boolean;\n"

    vhdl_str *= "\tbegin\n"
    vhdl_str *= "\t\twait for 12 ns;\n"

    vhdl_str *= "\t\twhile not endfile(outputsFile) loop\n"
    vhdl_str *= "\t\t\ttestCounter := testCounter + 1;\n"
    vhdl_str *= "\t\t\treadline(outputsFile, expectedOutput);\n"
    vhdl_str *= "\t\t\texpectedOutputString := expectedOutput.all & (expectedOutput'Length+1 to 10000 => ' ');\n"
    vhdl_str *= "\t\t\ttestSuccess := testLine(testCounter, expectedOutputString"

    for output_value in output_values
        output_name = output_naming_vhdl(output_value)
        vhdl_str *= ", $(output_name)"
    end
    vhdl_str *= ");\n"

    vhdl_str *= "\t\t\tif not testSuccess then\n"
    vhdl_str *= "\t\t\t\terrorCounter := errorCounter + 1;\n"
    vhdl_str *= "\t\t\tend if;\n"
    vhdl_str *= "\t\t\twait for 10 ns;\n"
    vhdl_str *= "\t\tend loop;\n"
    vhdl_str *= "\t\treport integer'image(errorCounter) & \" error(s) encoutered.\" severity note;\n"
    vhdl_str *= "\t\treport \"End of simulation after \" & integer'image(testCounter) & \" tests\" severity note;\n"
    vhdl_str *= "\tend process;\n\n"

    vhdl_str *= "end architecture;\n"

    return vhdl_str
end


function write_vhdl(
        addergraph::AdderGraph;
        vhdl_filename::String="addergraph.vhdl",
        vhdl_test_filename::String="addergraph_test.vhdl",
        no_addergraph::Bool=false,
        use_tables::Bool=false,
        verbose::Bool=false,
        with_tests::Bool=true,
        kwargs...
    )
    vhdl_str = ""
    if !no_addergraph
        _, vhdl_str, _ = vhdl_addergraph_generation(addergraph; verbose=verbose, kwargs...)
    elseif use_tables
        vhdl_str = vhdl_output_tables(addergraph; verbose=verbose, kwargs...)
    else
        vhdl_str = vhdl_output_products(addergraph; verbose=verbose, kwargs...)
    end
    open(vhdl_filename, "w") do writefile
        write(writefile, vhdl_str)
    end
    if with_tests
        vhdl_str = ""
        original_entity_name = ""
        if no_addergraph
            output_values = unique(get_outputs(addergraph))
            if use_tables
                original_entity_name = "Tables_"*entity_naming(output_values)
            else
                original_entity_name = "Products_"*entity_naming(output_values)
            end
        end
        vhdl_str = vhdl_test_generation(addergraph; verbose=verbose, original_entity_name=original_entity_name, kwargs...)
        open(vhdl_test_filename, "w") do writefile
            write(writefile, vhdl_str)
        end
        write_tests(addergraph; kwargs...)
    end
    return nothing
end


function write_tests(
        addergraph::AdderGraph;
        inputs_test::Vector{Int}=Vector{Int}(),
        wordlength_in::Int,
        inputs_filename::String="test.input",
        outputs_filename::String="test.output",
        signed::Bool=true,
        kwargs...
    )
    output_values = unique(get_outputs(addergraph))
    if isempty(inputs_test)
        if signed
            inputs_test = collect((-2^(wordlength_in-1)):(2^(wordlength_in-1)-1))
        else
            inputs_test = collect(0:(2^wordlength_in-1))
        end
    end
    @assert minimum(inputs_test) >= -2^(wordlength_in-signed)
    @assert maximum(inputs_test) <= 2^(wordlength_in-signed)-1
    open(inputs_filename, "w") do writefile_inputs
        open(outputs_filename, "w") do writefile_outputs
            for curr_input in inputs_test
                write(writefile_inputs, bitstring(curr_input)[(end-wordlength_in+1):end])
                write(writefile_inputs, "\n")
                output_value = output_values[1]
                shift = round(Int, log2(abs(output_value)/odd(abs(output_value))))
                wl_adder_dsp = 0
                if !done_with_dsp(addergraph, output_value)
                    addernode = get_output_addernode(addergraph, output_value)
                    wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in; signed=signed, kwargs...)
                else
                    dsp_value = get_output_dsp(addergraph, output_value)
                    wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in; signed=signed, kwargs...)
                end
                write(writefile_outputs, bitstring(output_value*curr_input)[(end-(wl_adder_dsp-1+shift)):end])
                for output_value in output_values[2:end]
                    shift = round(Int, log2(abs(output_value)/odd(abs(output_value))))
                    wl_adder_dsp = 0
                    if !done_with_dsp(addergraph, output_value)
                        addernode = get_output_addernode(addergraph, output_value)
                        wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in; signed=signed, kwargs...)
                    else
                        dsp_value = get_output_dsp(addergraph, output_value)
                        wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in; signed=signed, kwargs...)
                    end
                    write(writefile_outputs, " ")
                    write(writefile_outputs, bitstring(output_value*curr_input)[(end-(wl_adder_dsp-1+shift)):end])
                end
                write(writefile_outputs, "\n")
            end
        end
    end

    return nothing
end
