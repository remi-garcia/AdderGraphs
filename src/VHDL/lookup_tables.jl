function vhdl_output_tables(
        addergraph::AdderGraph;
        wordlength_in::Int,
        pipeline_inout::Bool=false,
        with_clk::Bool=true,
        target_frequency::Int,
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
        entity_name = "Tables_"*entity_naming(output_values)
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
    -- Generation of output LUTs
    """
    # https://stackoverflow.com/questions/21976749/design-of-a-vhdl-lut-module

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

    vhdl_str *= "attribute rom_style : string;\n"
    signal_input_name = "x_in"
    signal_input_wl = wordlength_in
    vhdl_str *= "signal $(signal_input_name) : std_logic_vector($(signal_input_wl-1) downto 0);\n"
    for output_value in output_values
        if output_value < 0 && -output_value in output_values
            continue
        end
        #TODO include truncations in LUTs
        wlout = round(Int, log2((2^(wordlength_in) - 1)*abs(output_value)), RoundUp)
        if twos_complement
            wlout = 1 + round(Int, log2(abs(abs(output_value) * (-(2^(wordlength_in-1))))), RoundUp)
        end
        lut_outputs = Vector{Vector{Bool}}([reverse(digits(abs(output_value)*i, base=2, pad=wlout))[1:wlout] for i in 0:((2^wordlength_in)-1)])
        if twos_complement
            lut_outputs = Vector{Vector{Bool}}([[parse(Int, curr_digit) for curr_digit in bitstring(abs(output_value)*i)][(end-wlout+1):end] for i in ((-2^(wordlength_in-1))):((2^(wordlength_in-1))-1)])
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
        \n\ttype lut_$(output_name) is array ($(twos_complement ? "integer" : "natural") range $(twos_complement ? -2^(wordlength_in-1) : 0) to $(twos_complement ? 2^(wordlength_in-1)-1 : 2^(wordlength_in)-1)) of std_logic_vector($(wl_adder_dsp-1) downto 0);
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
        vhdl_str *= "\t$(signal_output_naming(output_value)) <= $(output_value < 0 ? "-" : "")bitcount_$(output_name)(TO_INTEGER($(twos_complement ? "" : "un")signed($(signal_input_name))));\n"
    end

    vhdl_str *= "end architecture;\n"

    push!(vhdl_strs, (vhdl_str, entity_name))

    return vhdl_strs
end