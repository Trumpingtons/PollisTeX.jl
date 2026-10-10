"""
	PollisTeX

Runs Tectonic, a self-contained TeX/LaTeX engine (https://tectonic-typesetting.github.io). The Tectonic program
is downloaded the first time it is needed, and the TeX packages a document uses are downloaded by Tectonic itself
as it meets them.
"""
module PollisTeX

using Artifacts: artifact_meta, artifact_exists, artifact_path
using Base.BinaryPlatforms: HostPlatform, triplet
using Downloads: download
using ProgressLogging: @withprogress, @logprogress
using SHA: sha256
import Pkg

export tectonic, compile

const ARTIFACTS = joinpath(@__DIR__, "..", "Artifacts.toml")

"""The entry of Artifacts.toml for this machine."""
function build()
	meta = artifact_meta("tectonic", ARTIFACTS; platform = HostPlatform())
	meta === nothing && error("Tectonic has no build for $(triplet(HostPlatform())).")
	return meta
end

"""
	installed() -> Bool

Whether Tectonic is already downloaded on this machine.
"""
installed() = artifact_exists(Base.SHA1(build()["git-tree-sha1"]))

"""
	install() -> String

Downloads Tectonic for this machine (about 22 MB), if it isn't there yet, and returns the folder holding it. The
download is checked against the SHA-256 in Artifacts.toml and kept in the Julia depot (`~/.julia/artifacts`).
"""
function install()
	meta = build()
	tree = Base.SHA1(meta["git-tree-sha1"])
	artifact_exists(tree) && return artifact_path(tree)
	source = only(meta["download"])
	file = tempname()
	try
		download(source["url"], file)
		open(io -> bytes2hex(sha256(io)), file) == source["sha256"] ||
			error("The Tectonic download does not match its SHA-256: $(source["url"])")
		unpacked = Pkg.Artifacts.create_artifact(dir -> Pkg.PlatformEngines.unpack(file, dir))
		if unpacked != tree
			Pkg.Artifacts.remove_artifact(unpacked)
			error("The unpacked Tectonic does not match its git-tree-sha1: $(source["url"])")
		end
	finally
		rm(file; force = true)
	end
	return artifact_path(tree)
end

"""
	tectonic() -> String

The path of the Tectonic program, downloaded first if needed.
"""
tectonic() = joinpath(install(), Sys.iswindows() ? "tectonic.exe" : "tectonic")

"""
	version() -> VersionNumber

The version of Tectonic.
"""
version() = VersionNumber(match(r"\d+\.\d+\.\d+", readchomp(`$(tectonic()) --version`)).match)

"""
	Problem

An error or warning that Tectonic reported, with the file and line it points to (`line` is 0 when it has none).
"""
struct Problem
	kind::Symbol
	file::String
	line::Int
	message::String
end

Base.show(io::IO, p::Problem) = print(io, p.kind, ": ", p.file, p.line > 0 ? ":$(p.line)" : "", ": ", p.message)

"""
	Result

What [`compile`](@ref) produced: the PDF (`nothing` when there is none), the errors and warnings, the log file
and Tectonic's whole output.
"""
struct Result
	pdf::Union{String,Nothing}
	problems::Vector{Problem}
	log::Union{String,Nothing}
	output::String
end

function Base.show(io::IO, ::MIME"text/plain", r::Result)
	println(io, r.pdf === nothing ? "No PDF" : "PDF: $(r.pdf)")
	r.log === nothing || println(io, "Log: $(r.log)")
	foreach(p -> println(io, p), r.problems)
end

const PROBLEM = r"^(?<kind>error|warning): (?<file>[^:\n]+?):(?<line>\d+): (?<message>.*)$"

"""
	compile(file; outdir = dirname(file)) -> Result

Typesets a .tex file with Tectonic, which runs TeX, BibTeX and makeindex as many times as needed. The PDF and
the log go to `outdir`. TeX packages the document uses are downloaded the first time; the progress, reported
through ProgressLogging, shows in the status bar of Pollis or VS Code. The errors and warnings come back with the
line they point to, for whoever writes the file to fix them.
"""
function compile(file::AbstractString; outdir::AbstractString = dirname(abspath(file)))
	file = abspath(file)
	isfile(file) || throw(ArgumentError("No such file: $file"))
	program = tectonic()
	mkpath(outdir)
	output = IOBuffer()
	problems = Problem[]
	succeeded = @withprogress name = "Compiling $(basename(file))" begin
		pipe = Pipe()
		process = run(pipeline(ignorestatus(`$program --keep-logs --outdir $outdir $file`); stdout = pipe, stderr = pipe); wait = false)
		close(pipe.in)
		downloads = 0
		for line in eachline(pipe)
			println(output, line)
			if startswith(line, "note: downloading ")
				downloads += 1
				@logprogress "Downloading TeX files ($downloads)" nothing
			elseif (m = match(PROBLEM, line)) !== nothing
				push!(problems, Problem(Symbol(m[:kind]), m[:file], parse(Int, m[:line]), m[:message]))
			elseif (m = match(r"^error: (?<message>.*)$", line)) !== nothing && !any(p -> p.kind == :error, problems)
				# an error that points to no line, e.g. a missing file; kept only when no better error came first
				push!(problems, Problem(:error, basename(file), 0, m[:message]))
			end
		end
		success(process)
	end
	name = splitext(basename(file))[1]
	pdf = joinpath(outdir, name * ".pdf")
	log = joinpath(outdir, name * ".log")
	return Result(succeeded && isfile(pdf) ? pdf : nothing, problems, isfile(log) ? log : nothing, String(take!(output)))
end

const WARMUP = Dict(
	"article" => raw"""
		\documentclass{article}
		\usepackage{amsmath, amssymb, booktabs, graphicx, xcolor, geometry, hyperref}
		\begin{document}
		\section{Warm-up}
		$\hat\beta = (X^\top X)^{-1} X^\top y$
		\begin{tabular}{lr}\toprule a & 1 \\ \bottomrule\end{tabular}
		\end{document}
		""",
	"beamer" => raw"""
		\documentclass{beamer}
		\usepackage{amsmath, booktabs, graphicx}
		\begin{document}
		\begin{frame}{Warm-up}$\hat\beta = (X^\top X)^{-1} X^\top y$\end{frame}
		\end{document}
		""",
)

"""
	warmup()

Typesets two small documents, an article and beamer slides, so that Tectonic downloads the TeX files most
documents need (about a minute, once per machine; later compiles take seconds). The progress shows in the
status bar.
"""
function warmup()
	dir = mktempdir()
	for (name, source) in WARMUP
		file = joinpath(dir, "$name.tex")
		write(file, source)
		result = compile(file)
		result.pdf === nothing && error("The $name warm-up did not compile:\n$(result.output)")
	end
	return nothing
end

end
