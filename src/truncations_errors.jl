function get_truncations(addernode::AdderNode)
    return get_truncation.(get_input_edges(addernode))
end


function set_truncations!(addernode::AdderNode, truncations::Vector{Int})
    input_edges = get_input_edges(addernode)
    @assert length(truncations)==length(input_edges)
    for i in 1:length(input_edges)
        set_truncation!(input_edges[i], truncations[i])
    end
    return addernode
end


function read_addergraph_truncations(addergraph::AdderGraph, s::String)
    adders_registers_truncs = strip.(split(s, ";"))
    for val in adders_registers_truncs
        adder_valdepth, adder_trunc = strip.(split(val, ":"))
        if length(split(adder_trunc, ",")) == 1
            # Skip register
            println("Register ignored: $val")
            continue
        end
        adder_val, adder_depth = parse.(Int, strip.(split(adder_valdepth, ",")))
        addernodes = get_addernodes_by_value(addergraph, adder_val)
        current_addernode = nothing
        for addernode in addernodes
            if get_depth(addernode) == adder_depth
                current_addernode = addernode
            end
        end
        if current_addernode === nothing
            println("Adder not in addergraph, ignored: $val")
            continue
        end
        truncations = parse.(Int, strip.(split(adder_trunc, ",")))
        # for i in 1:length(truncations)
        #     if truncations[i] != 0
        #         truncations[i] += get_input_shifts(current_addernode)[i]
        #     end
        # end
        set_truncations!(current_addernode, truncations)
    end
    return addergraph
end


function write_addergraph_truncations(addergraph::AdderGraph; flopoco_format::Bool=true)
    adderstring = "truncations=\""
    firstcoefnocomma = true
    for addernode in get_nodes(addergraph)
        if !firstcoefnocomma
            adderstring *= "; "
        else
            firstcoefnocomma = false
        end
        adderstring *= "$(get_value(addernode)), $(get_depth(addernode)): "
        firsttruncnocomma = true
        truncations = get_truncations(addernode)
        shifts = get_input_shifts(addernode)
        for i in 1:length(truncations)
            truncation = truncations[i]
            shift = shifts[i]
            if !firsttruncnocomma
                adderstring *= ", "
            else
                firsttruncnocomma = false
            end
            # adderstring *= "$(max(truncation-shift, 0))"
            adderstring *= "$(truncation)"
        end
    end
    adderstring *= "\""
    return adderstring
end


function get_maximal_errors(addergraph::AdderGraph; wlIn::Int=-1, msbIn::Union{Int, Nothing}=nothing, lsbIn::Union{Int, Nothing}=nothing, verbose::Bool=false)::Union{Dict{Int, Int}, Dict{Int, Float64}}
    if wlIn != -1
        return _get_maximal_errors_wl(addergraph, wlIn=wlIn, verbose=verbose)
    elseif !isnothing(msbIn) && !isnothing(lsbIn)
        return _get_maximal_errors_lsbmsb(addergraph, msbIn=msbIn, lsbIn=lsbIn, verbose=verbose)
    else
        @error "Wrong arguments"
    end
    return Dict{Int, Int}()
end


function _get_maximal_errors_wl(addergraph::AdderGraph; wlIn::Int, verbose::Bool=false)::Dict{Int, Int}
    all_errors = Dict{Int, Int}([value => 0 for value in get_value.(get_nodes(addergraph))])
    for i in 0:(2^wlIn - 1)
        truncated_all = evaluate_adders(addergraph, i, wlIn=wlIn, verbose=verbose)
        exact_all = evaluate_adders(addergraph, i, wlIn=wlIn, apply_internal_truncations=false, verbose=verbose)
        for value in get_value.(get_nodes(addergraph))
            all_errors[value] = max(all_errors[value], abs(truncated_all[value]-exact_all[value]))
        end
    end
    return all_errors
end


function _get_maximal_errors_lsbmsb(addergraph::AdderGraph; msbIn::Int, lsbIn::Int, verbose::Bool=false)::Dict{Int, Float64}
    all_errors_int = get_errors(addergraph, wlIn=msbIn-lsbIn+1, verbose=verbose)
    all_errors = Dict{Int, Float64}([value => all_errors_int[value]*(2.0^lsbIn) for value in getvalues.(get_nodes(addergraph))])
    return all_errors
end


function pretty_print_get_maximal_output_errors(addergraph::AdderGraph; wlIn::Int=-1, msbIn::Union{Int, Nothing}=nothing, lsbIn::Union{Int, Nothing}=nothing, verbose::Bool=false)::Nothing
    dict_error = get_maximal_errors(addergraph, wlIn=wlIn, msbIn=msbIn, lsbIn=lsbIn, verbose=verbose)
    for (output, error_val) in dict_error
        println("Maximum error for output $output is equal to $error_val")
    end
    return nothing
end


function _get_maximal_output_errors_wl(addergraph::AdderGraph; wlIn::Int, verbose::Bool=false)::Dict{Int, Int}
    output_errors = Dict{Int, Int}([output_value => 0 for output_value in get_outputs(addergraph)])
    for i in 0:(2^wlIn - 1)
        truncated_outputs = evaluate(addergraph, i, wlIn=wlIn, verbose=verbose)
        exact_outputs = evaluate(addergraph, i, wlIn=wlIn, apply_internal_truncations=false, verbose=verbose)
        for output_value in get_outputs(addergraph)
            output_errors[output_value] = max(output_errors[output_value], abs(truncated_outputs[output_value]-exact_outputs[output_value]))
        end
    end
    return output_errors
end


function _get_maximal_output_errors_lsbmsb(addergraph::AdderGraph; msbIn::Int, lsbIn::Int, verbose::Bool=false)::Dict{Int, Float64}
    output_errors_int = get_maximal_errors(addergraph, wlIn=msbIn-lsbIn+1, verbose=verbose)
    output_errors = Dict{Int, Float64}([output_value => output_errors_int[output_value]*(2.0^lsbIn) for output_value in get_outputs(addergraph)])
    return output_errors
end


function get_maximal_output_errors(addergraph::AdderGraph; wlIn::Int=-1, msbIn::Union{Int, Nothing}=nothing, lsbIn::Union{Int, Nothing}=nothing, verbose::Bool=false)::Union{Dict{Int, Int}, Dict{Int, Float64}}
    if wlIn != -1
        return _get_maximal_output_errors_wl(addergraph, wlIn=wlIn, verbose=verbose)
    elseif !isnothing(msbIn) && !isnothing(lsbIn)
        return _get_maximal_output_errors_lsbmsb(addergraph, msbIn=msbIn, lsbIn=lsbIn, verbose=verbose)
    else
        @error "Wrong arguments"
    end
    return Dict{Int, Int}()
end
