include("$(@__DIR__())/utils.jl")
include("$(@__DIR__())/adder_graphs.jl")
include("$(@__DIR__())/lookup_tables.jl")
include("$(@__DIR__())/products.jl")
include("$(@__DIR__())/compressor_trees.jl")
include("$(@__DIR__())/tests.jl")
include("$(@__DIR__())/simulations.jl")
include("$(@__DIR__())/cmd.jl")

function write_vhdl(
        addergraph::AdderGraph;
        vhdl_filename::String="addergraph.vhdl",
        vhdl_test_filename::String="addergraph_test.vhdl",
        vhdl_simulation_filename::String="addergraph_simulation.vhdl",
        use_addergraph::Bool=true,
        use_tables::Bool=false,
        use_products::Bool=false,
        use_compressor_trees::Bool=false,
        entity_name::String="",
        verbose::Bool=false,
        with_tests::Bool=true,
        with_inputs_outputs::Bool=true,
        with_simulation::Bool=true,
        single_file::Bool=false,
        target_frequency::Int=200,
        ag_filename::String="",
        with_cmd::Bool=true,
        cmd_filename::String="cmd.sh",
        kwargs...
    )
    if !(use_addergraph || use_tables || use_products || use_compressor_trees)
        @warn "use_addergraph by default"
        use_addergraph = true
    end
    if count([use_addergraph, use_tables, use_products, use_compressor_trees]) >= 2
        @warn "Only adder graph, tables, products or compressor trees vhdl generation will be done"
    end
    if isempty(entity_name)
        if !use_addergraph
            output_values = unique(get_outputs(addergraph))
            if use_tables
                entity_name = "Tables_"*entity_naming(output_values)
            elseif use_products
                entity_name = "Products_"*entity_naming(output_values)
            else#if use_compressor_trees
                entity_name = "CompressorTrees_"*entity_naming(output_values)
            end
        end
    end

    vhdl_strs = Vector{String}()
    if use_addergraph
        entity_name, vhdl_strs, _ = vhdl_addergraph_generation(addergraph; entity_name=entity_name, verbose=verbose, target_frequency=target_frequency, kwargs...)
    elseif use_tables
        vhdl_strs = vhdl_output_tables(addergraph; verbose=verbose, entity_name=entity_name, target_frequency=target_frequency, kwargs...)
    elseif use_products
        vhdl_strs = vhdl_output_products(addergraph; verbose=verbose, entity_name=entity_name, target_frequency=target_frequency, kwargs...)
    else#if use_compressor_trees
        vhdl_strs = vhdl_output_compressortrees(addergraph; verbose=verbose, entity_name=entity_name, target_frequency=target_frequency, kwargs...)
    end
    base_vhdl_filename = string(vhdl_filename[1:findlast(==('.'), vhdl_filename)-1])
    if isempty(ag_filename)
        ag_filename = "$(base_vhdl_filename)_$(entity_name).vhdl"
    end
    if single_file
        open(vhdl_filename, "w") do writefile
            for (vhdl_str, _) in vhdl_strs
                write(writefile, vhdl_str)
                write(writefile, "\n\n\n")
            end
        end
    else
        for (vhdl_str, curr_entity_name) in vhdl_strs[1:end-1]
            open("$(base_vhdl_filename)_$(curr_entity_name).vhdl", "w") do writefile
                write(writefile, vhdl_str)
            end
        end
        open(ag_filename, "w") do writefile
            write(writefile, vhdl_strs[end][1])
        end
    end

    if with_tests
        vhdl_str = ""
        vhdl_str = vhdl_test_generation(
            addergraph;
            verbose=verbose,
            target_frequency=target_frequency,
            entity_name=entity_name,
            kwargs...
        )
        open(vhdl_test_filename, "w") do writefile
            write(writefile, vhdl_str)
        end
        if with_inputs_outputs
            write_tests(addergraph; kwargs...)
        end
    end
    if with_simulation
        vhdl_str = ""
        vhdl_str = vhdl_simulation_generation(
            addergraph;
            verbose=verbose,
            target_frequency=target_frequency,
            entity_name=entity_name,
            kwargs...
        )
        open(vhdl_simulation_filename, "w") do writefile
            write(writefile, vhdl_str)
        end
    end
    if with_cmd
        cmd_run_vivado = write_cmd(
            vhdl_strs;
            vhdl_filename=vhdl_filename,
            vhdl_test_filename=vhdl_test_filename,
            vhdl_simulation_filename=vhdl_simulation_filename,
            use_compressor_trees=use_compressor_trees,
            verbose=verbose,
            with_tests=with_tests,
            with_simulation=with_simulation,
            target_frequency=target_frequency,
            ag_filename=ag_filename,
            kwargs...
        )
        open(cmd_filename, "a") do writefile
            write(writefile, cmd_run_vivado)
        end
    end
    return nothing
end
