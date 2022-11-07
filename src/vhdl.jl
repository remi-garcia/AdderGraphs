function signal_naming(addernode::AdderNode)
    signal_input_left = "x_iL_$(get_value(addernode))_$(get_depth(addernode))"
    signal_input_right = "x_iR_$(get_value(addernode))_$(get_depth(addernode))"
    signal_output = "x_O_$(get_value(addernode))_$(get_depth(addernode))"
    return (signal_input_left, signal_input_right, signal_output)
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

function entity_naming(addernode::AdderNode)
    return "Addernode_$(get_value(addernode))_$(get_depth(addernode))"
end

function entity_naming(addergraph::AdderGraph)
    return "Addergraph_$(join(get_outputs(addergraph), "_"))"
end

function output_naming(output_value::Int)
    return "o$(output_value < 0 ? "minus" : "")$(abs(output_value))"
end

function signal_output_naming(output_value::Int)
    return "x_$(output_naming(output_value))"
end

function adder_port_names()
    return ("i_L", "i_R", "o_SUM")
end


function adder_generation(
        addernode::AdderNode, addergraph::AdderGraph;
        wordlength_in::Int,
        target_frequency::Int=400,
        verbose::Bool=false
    )
    vhdl_str = """
    --------------------------------------------------------------------------------
    --                      $(entity_naming(addernode))
    -- VHDL generated for Kintex7 @ $(target_frequency)MHz
    -- Authors: Rémi Garcia
    --------------------------------------------------------------------------------
    -- Target frequency (MHz): $(target_frequency)
    -- Input signals: $(adder_port_names()[1]) $(adder_port_names()[2])
    -- Output signals: $(adder_port_names()[3])

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
    input_signs = are_negative_inputs(addernode) # true is negative
    input_depths = get_input_depths(addernode)
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

    # Entity
    vhdl_str *= """
    -- Generation of addernode $(addernode_value) at depth $(addernode_depth)
    -- from inputs $(input_values[1]) and $(input_values[2]) at depths
    -- $(input_depths[1]) and $(input_depths[2])
    """

    entity_name = entity_naming(addernode)
    vhdl_str *= """
    entity $(entity_name) is
    """

    port_str = "port (\n"
    # vhdl_str *= "\t\tclk : in std_logic;"
    # vhdl_str *= " -- Clock\n"
    port_names = adder_port_names()
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
    if inputsum_max_wl != addernode_wl
        vhdl_str *= "signal $(signal_output_wl_adjusted_name) : std_logic_vector($(inputsum_max_wl-1) downto 0);"
        vhdl_str *= " -- Output signal with adjusted wordlength\n"
    else
        signal_output_wl_adjusted_name = signal_output_name
    end

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
    vhdl_str *= "\t$(signal_left_name) <= i_L;\n"
    vhdl_str *= "\t$(signal_right_name) <= i_R;\n"

    # Resize for shifts
    if input_shifts[1] > 0
        vhdl_str *= "\t$(signal_left_shifted_name) <= $(signal_left_name)($(signal_left_wl-1) downto 0) & \"$(repeat("0", input_shifts[1]))\";\n"
    end
    if input_shifts[2] > 0
        vhdl_str *= "\t$(signal_right_shifted_name) <= $(signal_right_name)($(signal_right_wl-1) downto 0) & \"$(repeat("0", input_shifts[2]))\";\n"
    end

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

    vhdl_str *= "\t$(signal_output_wl_adjusted_name) <= "
    vhdl_str *= "$(input_signs[1] ? "-" : "")"
    vhdl_str *= "std_logic_vector(signed($(signal_left_wl_adjusted_name))"
    vhdl_str *= " $(input_signs[2] ? "-" : "+") "
    vhdl_str *= "signed($(signal_right_wl_adjusted_name)));\n"

    if inputsum_max_wl != addernode_wl
        vhdl_str *= "\t$(signal_output_name) <= "
        vhdl_str *= "$(signal_output_wl_adjusted_name)($(inputsum_max_wl-1) downto $(inputsum_max_wl-addernode_wl))"
        vhdl_str *= ");\n"
    end
    vhdl_str *= "\to_SUM <= $(signal_output_name);\n"
    vhdl_str *= "end architecture;\n"

    return (entity_name, port_str, vhdl_str)
end


function vhdl_addergraph_generation(
        addergraph::AdderGraph;
        wordlength_in::Int, pipeline::Bool=false,
        pipeline_inout::Bool=false,
        target_frequency::Int=400,
        verbose::Bool=false
    )
    if get_adder_depth(addergraph) <= 1
        verbose && pipeline && println("WARNING: Pipeline not necessary for AD=$(get_adder_depth(addergraph))")
        pipeline = false
    end
    output_values = unique(get_outputs(addergraph))

    vhdl_str = ""
    adder_ports = Dict{String, String}()
    for addernode in get_nodes(addergraph)
        adder_entity_name, adder_port_str, adder_vhdl_str = adder_generation(addernode, addergraph; wordlength_in=wordlength_in, target_frequency=target_frequency)
        adder_ports[adder_entity_name] = adder_port_str
        vhdl_str *= adder_vhdl_str
        vhdl_str *= "\n\n\n"
    end

    vhdl_str *= """
    --------------------------------------------------------------------------------
    --                      $(entity_naming(addergraph))
    -- VHDL generated for Kintex7 @ $(target_frequency)MHz
    -- Authors: Rémi Garcia
    --------------------------------------------------------------------------------
    -- Target frequency (MHz): $(target_frequency)
    -- Input signals: clk input_x
    -- Output signals: $(join([output_naming(output_value) for output_value in output_values], " "))

    library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    library std;
    """

    # Entity
    vhdl_str *= """
    -- Generation of addergraph
    """

    entity_name = entity_naming(addergraph)
    vhdl_str *= """
    entity $(entity_name) is
        port (
    """
    # Always provide input clock for correct power results
    # if pipeline
        vhdl_str *= "\t\tclk : in std_logic;"
        vhdl_str *= " -- Clock\n"
    # end
    vhdl_str *= "\t\tinput_x : in std_logic_vector($(wordlength_in-1) downto 0);"
    vhdl_str *= " -- Input\n"
    if length(output_values) >= 2
        for output_value in output_values[1:(end-1)]
            output_name = output_naming(output_value)
            addernode = get_output_addernode(addergraph, output_value)
            vhdl_str *= "\t\t$(output_name): out std_logic_vector($(get_adder_wordlength(addernode, wordlength_in)-1) downto 0);"
            vhdl_str *= " -- Output $(output_value)\n"
        end
    end
    output_value = output_values[end]
    output_name = output_naming(output_value)
    addernode = get_output_addernode(addergraph, output_value)
    vhdl_str *= "\t\t$(output_name): out std_logic_vector($(get_adder_wordlength(addernode, wordlength_in)-1) downto 0)"
    vhdl_str *= " -- Output $(output_value)\n"
    vhdl_str *= "\t);\n"
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
        vhdl_str *= "signal $(signal_output_name)_$(get_depth(addernode))_register : std_logic_vector($(signal_output_wl-1) downto 0);\n"
    end
    for i in get_depth(addernode):(get_depth(addernode)+get_nb_registers(addernode, addergraph)-1+1)
        vhdl_str *= "signal $(signal_output_name)_$(i) : std_logic_vector($(signal_output_wl-1) downto 0);\n"
        if pipeline
            if i <= get_adder_depth(addergraph)-1
                vhdl_str *= "signal $(signal_output_name)_$(i)_register : std_logic_vector($(signal_output_wl-1) downto 0);\n"
            end
        end
        if pipeline_inout
            if i == get_adder_depth(addergraph)
                vhdl_str *= "signal $(signal_output_name)_$(i)_register : std_logic_vector($(signal_output_wl-1) downto 0);\n"
            end
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
            if pipeline_inout
                if i == get_adder_depth(addergraph)
                    vhdl_str *= "signal $(signal_output_name)_$(i)_register : std_logic_vector($(signal_output_wl-1) downto 0);\n"
                end
            end
        end
    end
    for output_value in output_values
        addernode = get_output_addernode(addergraph, output_value)
        output_name = signal_output_naming(output_value)
        vhdl_str *= "signal $(output_name) : std_logic_vector($(get_adder_wordlength(addernode, wordlength_in)-1) downto 0);\n"
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
                if i <= min(get_depth(addernode)+get_nb_registers(addernode, addergraph)-1, get_adder_depth(addergraph)-1)
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
            if get_depth(addernode)+get_nb_registers(addernode, addergraph)-1 == get_adder_depth(addergraph)
                vhdl_str *= "\t\t\t$(signal_output_name)_$(get_adder_depth(addergraph)) <= $(signal_output_name)_$(get_adder_depth(addergraph))_register;\n"
            end
            for addernode in get_nodes(addergraph)
                _, _, signal_output_name = signal_naming(addernode)
                if get_depth(addernode)+get_nb_registers(addernode, addergraph)-1 == get_adder_depth(addergraph)
                    vhdl_str *= "\t\t\t$(signal_output_name)_$(get_adder_depth(addergraph)) <= $(signal_output_name)_$(get_adder_depth(addergraph))_register;\n"
                end
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
    elseif pipeline_inout
        # Register to signals at clk
        vhdl_str *= "\t-- Add registers for pipelining\n"
        vhdl_str *= "\tprocess(clk)\n"
        vhdl_str *= "\tbegin\n"
        vhdl_str *= "\t\tif(rising_edge(clk)) then\n"
        for i in 0:1
            addernode = get_origin(addergraph)
            _, _, signal_output_name = signal_naming(addernode)
            if i*get_adder_depth(addergraph) >= get_depth(addernode)
                if i*get_adder_depth(addergraph) <= get_depth(addernode)+get_nb_registers(addernode, addergraph)-1
                    vhdl_str *= "\t\t\t$(signal_output_name)_$(i*get_adder_depth(addergraph)) <= $(signal_output_name)_$(i*get_adder_depth(addergraph))_register;\n"
                end
            end
            for addernode in get_nodes(addergraph)
                _, _, signal_output_name = signal_naming(addernode)
                if i*get_adder_depth(addergraph) >= get_depth(addernode)
                    if i*get_adder_depth(addergraph) <= get_depth(addernode)+get_nb_registers(addernode, addergraph)-1
                        vhdl_str *= "\t\t\t$(signal_output_name)_$(i*get_adder_depth(addergraph)) <= $(signal_output_name)_$(i*get_adder_depth(addergraph))_register;\n"
                    end
                end
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

    for output_value in output_values
        addernode = get_output_addernode(addergraph, output_value)
        output_name = signal_output_naming(output_value)
        _, _, signal_output_name = signal_naming(addernode)
        vhdl_str *= "\t$(output_name) <= $(signal_output_name)_$(get_adder_depth(addergraph));\n"
        ag_output_name = output_naming(output_value)
        vhdl_str *= "\t$(ag_output_name) <= $(output_name);\n"
    end
    vhdl_str *= ""

    vhdl_str *= "end architecture;\n"

    return vhdl_str
end


function write_vhdl(
        addergraph::AdderGraph;
        vhdl_filename::String="addergraph.vhdl",
        verbose::Bool=false,
        kwargs...
    )
    vhdl_str = vhdl_addergraph_generation(addergraph; verbose=verbose, kwargs...)
    open(vhdl_filename, "w") do writefile
        write(writefile, vhdl_str)
    end
    return nothing
end
