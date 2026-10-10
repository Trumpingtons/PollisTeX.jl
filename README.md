# PollisTeX.jl

Typeset LaTeX documents from Julia, with nothing to install but this package.

PollisTeX.jl downloads and runs [Tectonic](https://github.com/tectonic-typesetting/tectonic) (MIT), a complete,
self-contained TeX/LaTeX engine. The Tectonic program (about 22 MB) is downloaded the first time it is needed and
kept in the Julia depot. The TeX packages a document uses are downloaded by Tectonic as it meets them and cached,
so the first document takes a minute or so and later ones a few seconds.

## Usage

```julia
using PollisTeX

r = compile("report.tex")   # typesets report.tex; the PDF and the log go next to it
r.pdf                       # the PDF, or nothing if there were errors
r.problems                  # the errors and warnings, each with its file and line
```

A failed compile returns the errors instead of throwing:

```
julia> compile("report.tex")
No PDF
Log: /home/me/report.log
error: report.tex:5: Undefined control sequence
```

Tectonic runs TeX, BibTeX and makeindex as many times as the document needs. Pass `outdir` to put the PDF and the
log elsewhere: `compile("report.tex"; outdir = "build")`.

To run Tectonic yourself, `tectonic()` returns the path of the program and `PollisTeX.version()` its version:

```julia
run(`$(tectonic()) --help`)
```

## Platforms

macOS (Apple Silicon and Intel), Linux (x86_64 and aarch64, glibc and musl) and Windows (x86_64), from
Tectonic's own release builds. Each download is checked against the SHA-256 in `Artifacts.toml`, which
`gen/artifacts.jl` writes from the release.

## Notes

- Tectonic uses XeTeX, so documents can use Unicode and system fonts (`fontspec`).
- Tectonic's TeX bundle is based on TeX Live 2022.
- The first compile needs internet access; after that, documents that use only cached packages compile offline.

## License

MIT. Tectonic is distributed under the MIT license by the Tectonic Project.
