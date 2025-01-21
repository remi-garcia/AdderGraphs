function write_cmd(
        vhdl_strs::Vector{Tuple{String, String}}
        ;
        vhdl_filename::String,
        vhdl_test_filename::String,
        vhdl_simulation_filename::String,
        use_compressor_trees::Bool,
        verbose::Bool,
        with_tests::Bool,
        with_simulation::Bool,
        target_frequency::Int,
        ag_filename::String,
        cmd_tests::Bool=false,
        cmd_simulation::Bool=false,
        cmd_part::String="xc7k70tfbv484-3",
        cmd_project::String="",
        cmd_results::String="",
        cmd_keep::Bool=false,
        cmd_implement::Bool=true,
        cmd_delay::Bool=true,
        cmd_tcl::Bool=false,
        cmd_ooc_entities::Bool=false,
        kwargs...
    )
    if cmd_tests
        with_tests = true
    end
    if cmd_simulation
        with_simulation = true
    end
    base_vhdl_filename = string(vhdl_filename[1:findlast(==('.'), vhdl_filename)-1])
    cmd_run_vivado = "run_vivado.sh -v --part $(cmd_part) -f $(target_frequency)"
    if !isempty(cmd_project)
        cmd_run_vivado *= " -p=$(cmd_project)"
    end
    if !isempty(cmd_results)
        cmd_run_vivado *= " -r=$(cmd_results)"
    end
    if cmd_keep
        cmd_run_vivado *= " -k"
    end
    if cmd_implement
        cmd_run_vivado *= " -i"
    end
    if cmd_delay
        cmd_run_vivado *= " -d"
    end
    if cmd_tcl
        cmd_run_vivado *= " -t"
    end
    if with_tests
        cmd_run_vivado *= " -bs $(vhdl_test_filename)"
    end
    if with_simulation
        cmd_run_vivado *= " -s $(vhdl_simulation_filename)"
    end
    cmd_run_vivado *= " -vhdl $(ag_filename)"
    if length(vhdl_strs) > 1
        for (vhdl_str, curr_entity_name) in vhdl_strs[1:end-1]
            cmd_run_vivado *= " -avhdl $(base_vhdl_filename)_$(curr_entity_name).vhdl"
            if cmd_ooc_entities
                if use_compressor_trees
                    if occursin("comb_uid", curr_entity_name)
                        continue
                    end
                end
                cmd_run_vivado *= " --ooc_entity $(curr_entity_name)"
            end
        end
    end
    cmd_run_vivado *= "\n"

    return cmd_run_vivado
end