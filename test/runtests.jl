using PollisTeX
using Test

const DOCUMENT = raw"""
\documentclass{article}
\usepackage{amsmath}
\begin{document}
The model is $y = \beta_0 + \beta_1 x + \varepsilon$.
\end{document}
"""

@testset "PollisTeX" begin
	@test PollisTeX.version() == v"0.17.0"

	mktempdir() do dir
		good = joinpath(dir, "good.tex")
		write(good, DOCUMENT)
		r = compile(good)
		@test (r.pdf, r.problems) == (joinpath(dir, "good.pdf"), PollisTeX.Problem[])
		@test startswith(read(r.pdf, String), "%PDF")

		bad = joinpath(dir, "bad.tex")
		write(bad, replace(DOCUMENT, "The model" => "\\nosuchmacro The model"))
		r = compile(bad; outdir = joinpath(dir, "build"))
		@test (r.pdf, r.problems) == (nothing, [PollisTeX.Problem(:error, "bad.tex", 4, "Undefined control sequence")])
		@test r.log == joinpath(dir, "build", "bad.log")
	end
	@testset "warmup" begin
		@test PollisTeX.warmup() === nothing
	end
end
