# Writes ../Artifacts.toml from the official Tectonic release builds.
#
#     julia gen/artifacts.jl
#
# Each build is downloaded, checked against the SHA-256 that GitHub publishes for it, unpacked and hashed.
# Julia artifacts can't unpack every build: Windows comes as a .zip, and the Linux glibc tarball holds a sparse
# file. Those are repacked as plain .tar.gz files in gen/out/repacked/; attach them to the PollisTeX.jl release
# named in RELEASE. The other builds are downloaded from Tectonic's own release.
# To move to a new Tectonic, change TECTONIC and run this again.

using Downloads, SHA, Tar, TOML
using Pkg.Artifacts: create_artifact, artifact_path
using Pkg.PlatformEngines: unpack

const TECTONIC = v"0.17.0"
const UPSTREAM = "https://github.com/tectonic-typesetting/tectonic/releases/download/tectonic%40$TECTONIC"
const RELEASE = "https://github.com/Trumpingtons/PollisTeX.jl/releases/download/tectonic-$TECTONIC"
const OUT = joinpath(@__DIR__, "out")

# Julia platform => upstream build. The musl builds are static, so they also serve glibc on aarch64.
const PLATFORMS = [
	(Dict("os" => "macos", "arch" => "aarch64"), "aarch64-apple-darwin"),
	(Dict("os" => "macos", "arch" => "x86_64"), "x86_64-apple-darwin"),
	(Dict("os" => "linux", "arch" => "x86_64", "libc" => "glibc"), "x86_64-unknown-linux-gnu"),
	(Dict("os" => "linux", "arch" => "x86_64", "libc" => "musl"), "x86_64-unknown-linux-musl"),
	(Dict("os" => "linux", "arch" => "aarch64", "libc" => "glibc"), "aarch64-unknown-linux-musl"),
	(Dict("os" => "linux", "arch" => "aarch64", "libc" => "musl"), "aarch64-unknown-linux-musl"),
	(Dict("os" => "windows", "arch" => "x86_64"), "x86_64-pc-windows-msvc"),
]

"""The SHA-256 that GitHub publishes for each asset of the release."""
function published_digests()
	io = IOBuffer()
	Downloads.download("https://api.github.com/repos/tectonic-typesetting/tectonic/releases/tags/tectonic%40$TECTONIC", io)
	text = String(take!(io))
	digests = Dict{String,String}()
	name = nothing
	for m in eachmatch(r"\"name\":\s*\"(?<name>tectonic-[^\"]+)\"|\"digest\":\s*\"sha256:(?<sha>[0-9a-f]{64})\"", text)
		if m[:name] !== nothing
			name = m[:name]
		elseif name !== nothing
			digests[name] = m[:sha]
			name = nothing
		end
	end
	return digests
end

sha256_of(file) = open(io -> bytes2hex(sha256(io)), file)

"""Repacks a build as a plain .tar.gz holding the same files, with Julia's own platform name."""
function repack(file, build)
	dir = mktempdir()
	endswith(file, ".zip") ? run(`unzip -q $file -d $dir`) : run(`tar -xzf $file -C $dir`)
	triplet = replace(build, "-pc-windows-msvc" => "-w64-mingw32", "-unknown-linux-gnu" => "-linux-gnu")
	tarball = joinpath(OUT, "repacked", "tectonic-$TECTONIC-$triplet.tar.gz")
	mkpath(dirname(tarball))
	open(pipeline(`gzip -9 -n`; stdout = tarball), "w") do gz
		Tar.create(dir, gz)
	end
	return tarball
end

"""Whether Julia's artifact unpacker can read this file."""
unpackable(file) = endswith(file, ".tar.gz") && try
	unpack(file, mktempdir())
	true
catch
	false
end

function main()
	mkpath(OUT)
	digests = published_digests()
	entries = Dict{String,Any}[]
	downloaded = Dict{String,Tuple{String,String,String}}()  # build => (url, sha256, git-tree-sha1)
	for (platform, build) in PLATFORMS
		if !haskey(downloaded, build)
			asset = "tectonic-$TECTONIC-$build" * (occursin("windows", build) ? ".zip" : ".tar.gz")
			file = joinpath(OUT, asset)
			isfile(file) || Downloads.download("$UPSTREAM/$asset", file)
			sha256_of(file) == digests[asset] || error("$asset does not match the published SHA-256")
			url = "$UPSTREAM/$asset"
			if !unpackable(file)
				file = repack(file, build)
				url = "$RELEASE/$(basename(file))"
			end
			tree = create_artifact(dir -> unpack(file, dir))
			downloaded[build] = (url, sha256_of(file), bytes2hex(tree.bytes))
			println(rpad(build, 28), url == "$UPSTREAM/$asset" ? "upstream " : "repacked ", join(readdir(artifact_path(tree)), " "))
		end
		url, sha, tree = downloaded[build]
		push!(entries, merge(platform, Dict(
			"git-tree-sha1" => tree,
			"lazy" => true,
			"download" => [Dict("url" => url, "sha256" => sha)],
		)))
	end
	open(joinpath(@__DIR__, "..", "Artifacts.toml"), "w") do io
		println(io, "# Tectonic $TECTONIC, written by gen/artifacts.jl. Do not edit by hand.\n")
		TOML.print(io, Dict("tectonic" => entries); sorted = true)
	end
end

main()
