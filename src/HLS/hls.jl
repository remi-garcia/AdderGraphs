include("$(@__DIR__())/utils.jl")
include("$(@__DIR__())/adder_graphs.jl")

function write_hls(
        addergraph::AdderGraph;
        hls_filename::String="addergraph.cpp",
        verbose::Bool=false,
        kwargs...
    )
    hls_str = ""
    _, hls_str = hls_addergraph_generation(addergraph; verbose=verbose, kwargs...)
    open(hls_filename, "w") do writefile
        write(writefile, hls_str)
    end
    return nothing
end
