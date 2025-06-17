function vhdl_output_products(
        addergraph::AdderGraph;
        wordlength_in::Int,
        pipeline_inout::Bool=false,
        with_clk::Bool=true,
        target_frequency::Int,
        force_dsp::Bool=false,
        verbose::Bool=false,
        entity_name::String="",
        twos_complement::Bool=true,
        kwargs...
    )
    if pipeline_inout
        with_clk = true
    end
    output_values = unique(get_outputs(addergraph))
    if isempty(entity_name)
        entity_name = "Products_"*entity_naming(output_values)
    end

    vhdl_strs = Vector{Tuple{String, String}}()
    vhdl_str = """
    --------------------------------------------------------------------------------
    --                      $(entity_name)
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
    # Always provide input clock for correct power results with script
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

    push!(vhdl_strs, (vhdl_str, entity_name))

    return vhdl_strs
end
