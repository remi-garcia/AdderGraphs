function vhdl_output_compressortrees(
        addergraph::AdderGraph;
        wordlength_in::Int,
        pipeline_inout::Bool=false,
        with_clk::Bool=true,
        target_frequency::Int,
        verbose::Bool=false,
        entity_name::String="",
        twos_complement::Bool=true,
        flopoco_base_vhdl_folder::String="",
        flopoco_silent::Bool=true,
        kwargs...
    )
    flopoco_base_vhdl_folder = rstrip(flopoco_base_vhdl_folder, '/')
    if pipeline_inout
        with_clk = true
    end
    output_values = unique(get_outputs(addergraph))
    if isempty(entity_name)
        entity_name = "CompressorTree_"*entity_naming(output_values)
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
            shift = round(Int, log2(abs(output_value)/odd(abs(output_value))))
            wl_adder_dsp = 0
            if !done_with_dsp(addergraph, output_value)
                addernode = get_output_addernode(addergraph, output_value)
                wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in)
            else
                dsp_value = get_output_dsp(addergraph, output_value)
                wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in)
            end
            vhdl_str *= "\t\t$(output_name) : out std_logic_vector($(wl_adder_dsp-1+shift) downto 0);"
            vhdl_str *= " -- Output $(output_value)\n"
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
    vhdl_str *= "\t\t$(output_name) : out std_logic_vector($(wl_adder_dsp-1+shift) downto 0)"
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
    vhdl_str *= "signal $(signal_input_name) : std_logic_vector($(signal_input_wl-1) downto 0);\n\n"

    flopoco_filename = tempname()
    wl_ct = Dict{Int, Int}()
    for output_value in unique(odd.(abs.(output_values)))
        curr_ct_entity = ct_entity_naming(output_value)
        if isfile("$(flopoco_base_vhdl_folder)/$(output_value).vhdl")
            cp("$(flopoco_base_vhdl_folder)/$(output_value).vhdl", flopoco_filename; force=true)
        else
            #DONE flopoco gen cmd
            wl_adder_dsp = 0
            if !done_with_dsp(addergraph, output_value)
                addernode = get_output_addernode(addergraph, output_value)
                wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in)
            else
                dsp_value = get_output_dsp(addergraph, output_value)
                wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in)
            end
            curr_bitstring = reverse(bitstring(output_value)[(end-wl_adder_dsp+1):end])
            nb_ones = count(i->(i=='1'), curr_bitstring)
            curr_shifts = [i[1]-1 for i in collect.(findall(r"1", curr_bitstring))]
            flopoco_cmd = "flopoco useTargetOpt=1 FixMultiAdder signedIn=$(twos_complement ? "1" : "0") n=$(nb_ones) msbIn=$(join(repeat([wordlength_in-1], nb_ones), ":")) lsbIn=$(join(repeat([0], nb_ones), ":")) shifts=$(join(curr_shifts, ":")) generateFigures=0 compression=optimal name=$(curr_ct_entity) outputFile=$(flopoco_filename)"
            argv = Vector{String}(string.(split(flopoco_cmd)))
            if flopoco_silent
                pout = Pipe()
                perr = Pipe()
                run(pipeline(`$(argv)`; stdout = pout, stderr = perr))
                close(pout.in)
                close(perr.in)
            else
                println(flopoco_cmd)
                run(`$(argv)`)
            end
            if isdir(flopoco_base_vhdl_folder)
                @assert !isfile("$(flopoco_base_vhdl_folder)/$(output_value).vhdl")
                cp(flopoco_filename, "$(flopoco_base_vhdl_folder)/$(output_value).vhdl")
            end
        end

        #DONE split file into multiple strings
        splitpoint = "end architecture;"
        flopoco_strs = split(read(flopoco_filename, String), splitpoint) .* splitpoint
        pop!(flopoco_strs)
        rm(flopoco_filename)

        #DONE Read entities and rename them (replace in strings)
        flopoco_prev_entities = Vector{String}()
        curr_ct_ports = ""
        for i in 1:(length(flopoco_strs)-1)
            flopoco_str = flopoco_strs[i]
            curr_entity = strip(match(r"(?<=entity)(.*)(?=is)", flopoco_str).captures[1])
            push!(flopoco_prev_entities, "$(curr_entity)")
            flopoco_strs[i] = replace(flopoco_str, curr_entity => "$(curr_ct_entity)_$(curr_entity)")
            curr_entity = "$(curr_ct_entity)_$(curr_entity)"
            push!(vhdl_strs, (flopoco_strs[i], curr_entity))
        end
        flopoco_str = flopoco_strs[end]
        curr_entity = strip(match(r"(?<=entity)(.*)(?=is)", flopoco_str).captures[1])
        flopoco_strs[end] = replace(flopoco_strs[end], curr_entity => curr_ct_entity)
        flopoco_strs[end] = replace(flopoco_str, [prev_entity => "$(curr_ct_entity)_$(prev_entity)" for prev_entity in flopoco_prev_entities]...)
        # The following "works" but leads to the following error: ERROR: PCRE.exec error: JIT stack limit reached
        #curr_ct_ports = "port " * strip(match(r"(?<=port)((.|\n)*)(?=end entity)", flopoco_str).captures[1])
        curr_ct_ports = ""
        first_marker = false
        for curr_line in split(flopoco_strs[end], "\n")
            if !first_marker
                if occursin("port (R", curr_line)
                    first_marker = true
                    curr_ct_ports *= strip(curr_line)
                    curr_ct_ports *= "\n"
                end
            else
                if occursin("end entity;", curr_line)
                    break
                end
                curr_ct_ports *= curr_line
                curr_ct_ports *= "\n"
            end
        end
        wl_ct[output_value] = parse(Int, strip(match(r"(?<=std_logic_vector\()((.)*)(?=downto)", split(curr_ct_ports, "\n")[1]).captures[1]))+1
        push!(vhdl_strs, (flopoco_strs[end], curr_entity))

        #DONE components
        vhdl_str *= "\tcomponent $(curr_ct_entity) is\n"
        vhdl_str *= "\t\t$(curr_ct_ports)\n"
        vhdl_str *= "\tend component;\n\n"
    end
    for output_value in unique(odd.(abs.(output_values)))
        #TODO include truncations
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
        if wl_adder_dsp != wl_ct[output_value]
            vhdl_str *= "signal $(output_name)_ct : std_logic_vector($(wl_ct[output_value]-1) downto 0);\n"
        end
    end

    vhdl_str *= "\nbegin\n"
    if !pipeline_inout
        vhdl_str *= "\t$(signal_input_name) <= input_x;\n"
        for output_value in output_values
            shift = round(Int, log2(abs(output_value)/odd(abs(output_value))))
            vhdl_str *= "\t$(output_naming_vhdl(output_value)) <= $(sign(output_value) == -1 ? "-" : "")$(signal_output_naming(odd(abs(output_value))))$(shift != 0 ? " & \"$(repeat("0", shift))\"" : "");\n"
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
            shift = round(Int, log2(abs(output_value)/odd(abs(output_value))))
            vhdl_str *= "\t$(output_naming_vhdl(output_value)) <= $(sign(output_value) == -1 ? "-" : "")$(signal_output_naming(odd(abs(output_value))))$(shift != 0 ? " & \"$(repeat("0", shift))\"" : "");\n"
        end
        vhdl_str *= "\t\tend if;\n"
        vhdl_str *= "\tend process;\n"
    end

    for output_value in unique(odd.(abs.(output_values)))
        wl_adder_dsp = 0
        if !done_with_dsp(addergraph, output_value)
            addernode = get_output_addernode(addergraph, output_value)
            wl_adder_dsp = get_adder_wordlength(addernode, wordlength_in)
        else
            dsp_value = get_output_dsp(addergraph, output_value)
            wl_adder_dsp = get_dsp_wordlength(dsp_value, wordlength_in)
        end
        curr_ct_entity = ct_entity_naming(output_value)
        output_name = signal_output_naming(abs(output_value))
        vhdl_str *= "\tct_$(output_value): $(curr_ct_entity)\n"
        vhdl_str *= "\t\tport map (\n"
        curr_bitstring = reverse(bitstring(output_value)[(end-wl_adder_dsp+1):end])
        nb_ones = count(i->(i=='1'), curr_bitstring)
        for i in 1:nb_ones
            vhdl_str *= "\t\t\tX$(i-1) => $(signal_input_name),\n"
        end
        if wl_adder_dsp != wl_ct[output_value]
            vhdl_str *= "\t\t\tR => $(signal_output_naming(output_value))_ct\n"
        else
            vhdl_str *= "\t\t\tR => $(signal_output_naming(output_value))\n"
        end
        vhdl_str *= "\t\t);\n"
        if wl_adder_dsp != wl_ct[output_value]
            vhdl_str *= "\t$(signal_output_naming(output_value)) <= $(signal_output_naming(output_value))_ct($(wl_adder_dsp-1) downto 0);\n"
        end
        vhdl_str *= "\n"
    end

    vhdl_str *= "end architecture;\n"

    push!(vhdl_strs, (vhdl_str, entity_name))

    return vhdl_strs
end