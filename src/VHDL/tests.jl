function vhdl_test_generation(
        addergraph::AdderGraph;
        wordlength_in::Int,
        with_clk::Bool=true,
        verbose::Bool=false,
        pipeline::Bool=false,
        pipeline_inout::Bool=false,
        target_frequency::Int,
        entity_name::String="",
        tests_entity_name::String="",
        inputs_filename::String="test.input",
        outputs_filename::String="test.output",
        twos_complement::Bool=true,
        kwargs...
    )
    output_values = unique(get_outputs(addergraph))

    vhdl_str = ""
    original_entity_name = entity_name
    if isempty(original_entity_name)
        original_entity_name = entity_naming(addergraph)
    end
    if isempty(tests_entity_name)
        tests_entity_name = "TEST_"*original_entity_name
    end
    vhdl_str *= """
    --------------------------------------------------------------------------------
    --                      $(tests_entity_name)
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
    -- Generation of tests
    """

    vhdl_str *= "entity $(tests_entity_name) is\n"
    vhdl_str *= "end entity;\n"
    vhdl_str *= "\n"

    # Architecture
    vhdl_str *= """
    architecture behavioral of $(tests_entity_name) is
    """
    vhdl_str *= "\tcomponent $(original_entity_name) is\n"

    port_str = "\t\tport (\n"
    # vhdl_str *= "\t\tclk : in std_logic;"
    # vhdl_str *= " -- Clock\n"

    # Always provide input clock for correct power results with script
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

    vhdl_str *= "constant FREQ      : real := $(target_frequency*1e6);\n"
    vhdl_str *= "constant PERIOD    : time := 1 sec / FREQ;        -- Full period\n"
    vhdl_str *= "constant HIGH_TIME : time := PERIOD / 2;          -- High time\n"
    vhdl_str *= "constant LOW_TIME  : time := PERIOD - HIGH_TIME;  -- Low time -- always >= HIGH_TIME\n\n"
    #vhdl_str *= "assert (HIGH_TIME /= 0 fs) report \"clk_plain: High time is zero; time resolution to large for frequency\" severity FAILURE;\n\n"

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
        vhdl_str *= "\t\telse\n"
        vhdl_str *= "\t\t\treport \"For $(output_name): expected \" & integer'image(to_integer($(twos_complement ? "" : "un")signed(to_stdlogicvector(expected_$(output_name))))) & \" but got \" & integer'image(to_integer($(twos_complement ? "" : "un")signed($(output_name)))) severity note;\n"
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
            wait for LOW_TIME;
            clk <= '1';
            wait for HIGH_TIME;
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
            -- wait for 10*PERIOD; -- Initialize
            rst <= '1';
            wait for PERIOD;
            rst <= '0';
    """

    vhdl_str *= "\t\twhile not endfile(inputsFile) loop\n"
    vhdl_str *= "\t\t\treadline(inputsFile, input);\n"
    vhdl_str *= "\t\t\tread(input, v_input_x);\n"
    vhdl_str *= "\t\t\tinput_x <= to_stdlogicvector(v_input_x);\n"
    vhdl_str *= "\t\t\twait for PERIOD;\n"
    vhdl_str *= "\t\tend loop;\n"
    vhdl_str *= "\tend process;\n\n"

    vhdl_str *= "\tprocess\n"
    vhdl_str *= "\t\tvariable expectedOutput : line;\n"
    vhdl_str *= "\t\tvariable expectedOutputString : string(1 to 10000);\n"
    vhdl_str *= "\t\tfile outputsFile : text open read_mode is in \"$(outputs_filename)\";\n"
    vhdl_str *= "\t\tvariable testCounter : integer := 0;\n"
    vhdl_str *= "\t\tvariable errorCounter : integer := 0;\n"
    vhdl_str *= "\t\tvariable testSuccess : boolean;\n"

    vhdl_str *= "\tbegin\n"
    vhdl_str *= "\t\t-- wait for 10*PERIOD; -- Initialize\n"
    vhdl_str *= "\t\twait for PERIOD; -- For rst\n"
    vhdl_str *= "\t\twait for HIGH_TIME; -- For evaluation\n"
    if pipeline
        vhdl_str *= "\t\twait for PERIOD*$(get_adder_depth(addergraph)-1); -- For pipeline\n"
    elseif pipeline_inout
        vhdl_str *= "\t\twait for PERIOD*2; -- For pipeline\n"
    end

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
    vhdl_str *= "\t\t\twait for PERIOD;\n"
    vhdl_str *= "\t\tend loop;\n"
    vhdl_str *= "\t\treport integer'image(errorCounter) & \" error(s) encoutered.\" severity note;\n"
    vhdl_str *= "\t\treport \"End of simulation after \" & integer'image(testCounter) & \" tests\" severity note;\n"
    vhdl_str *= "\t\tassert errorCounter = 0 report \"Errors in simulation.\" severity error;\n"
    vhdl_str *= "\t\tstop;\n"
    vhdl_str *= "\tend process;\n\n"

    vhdl_str *= "end architecture;\n"

    return vhdl_str
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
