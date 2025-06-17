function vhdl_simulation_generation(
        addergraph::AdderGraph;
        wordlength_in::Int,
        with_clk::Bool=true,
        verbose::Bool=false,
        target_frequency::Int,
        entity_name::String="",
        simulation_entity_name::String="",
        simulation_inputs_filename::String="test.input",
        kwargs...
    )
    output_values = unique(get_outputs(addergraph))

    vhdl_str = ""

    original_entity_name = entity_name
    if isempty(original_entity_name)
        original_entity_name = entity_naming(addergraph)
    end
    if isempty(simulation_entity_name)
        simulation_entity_name = "SIM_"*original_entity_name
    end
    vhdl_str *= """
    --------------------------------------------------------------------------------
    --                      $(simulation_entity_name)
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
    library work;
    use std.env.stop;\n
    """

    # Entity
    vhdl_str *= """
    -- Generation of simulation
    """

    vhdl_str *= "entity $(simulation_entity_name) is\n"
    vhdl_str *= "end entity;\n"
    vhdl_str *= "\n"

    # Architecture
    vhdl_str *= """
    architecture behavioral of $(simulation_entity_name) is
    """
    vhdl_str *= "\tcomponent $(original_entity_name) is\n"

    port_str = "\t\tport (\n"
    # Always provide input clock for correct power results with script
    if with_clk
        port_str *= "\t\t\tclk : in std_logic;"
        port_str *= " -- Clock\n"
    end
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

    vhdl_str *= "constant FREQ      : real := $(target_frequency*1e6);\n"
    vhdl_str *= "constant PERIOD    : time := 1 sec / FREQ;        -- Full period\n"
    vhdl_str *= "constant HIGH_TIME : time := PERIOD / 2;          -- High time\n"
    vhdl_str *= "constant LOW_TIME  : time := PERIOD - HIGH_TIME;  -- Low time -- always >= HIGH_TIME\n\n"

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

    vhdl_str *= "begin\n"
    vhdl_str *= """
        -- Ticking clock signal
        process
        begin
            clk <= '0';
            wait for LOW_TIME;
            clk <= '1';
            wait for HIGH_TIME;
        end process;
    """

    vhdl_str *= "\n\tsimulation: $(original_entity_name)\n"
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
    vhdl_str *= "\t\tfile inputsFile : text open read_mode is in \"$(simulation_inputs_filename)\";\n"
    vhdl_str *= "\t\tvariable v_input_x : bit_vector($(wordlength_in-1) downto 0);\n"
    vhdl_str *= "\t\tvariable simCounter : integer := 0;\n"

    vhdl_str *= """
        begin
            -- wait for 10*PERIOD; -- Initialize
            rst <= '1';
            wait for PERIOD;
            rst <= '0';
    """

    vhdl_str *= "\t\twhile not endfile(inputsFile) loop\n"
    vhdl_str *= "\t\t\tsimCounter := simCounter + 1;\n"
    vhdl_str *= "\t\t\treadline(inputsFile, input);\n"
    vhdl_str *= "\t\t\tread(input, v_input_x);\n"
    vhdl_str *= "\t\t\tinput_x <= to_stdlogicvector(v_input_x);\n"
    vhdl_str *= "\t\t\twait for PERIOD;\n"
    vhdl_str *= "\t\tend loop;\n"
    vhdl_str *= "\t\treport \"End of simulation after \" & integer'image(simCounter) & \" inputs\" severity note;\n"
    vhdl_str *= "\t\tstop;\n"
    vhdl_str *= "\tend process;\n\n"
    vhdl_str *= "end architecture;\n"

    return vhdl_str
end
