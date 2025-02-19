using SpeciesDistributionToolkit
using Random
using DelimitedFiles
Random.seed!(420)

CHE = SpeciesDistributionToolkit.gadm("CHE")

bbox = (left = 0.0, right = 20.0, bottom = 35.0, top = 55.0)

# CHELSA data
provider = RasterData(CHELSA2, BioClim)
bioclim = [SDMLayer(provider; layer = l, bbox...) for l in layers(provider)]

# Landcover data
provider = RasterData(EarthEnv, LandCover)
landcover = [SDMLayer(provider; layer = l, bbox...) for l in layers(provider)]

# Trim and mask
bioclim = [trim(mask!(layer, CHE)) for layer in bioclim]
landcover = [trim(mask!(layer, CHE)) for layer in landcover]

# Transfer the landcover layers to bioclim using interpolate
itrp = (l) -> interpolate(convert(SDMLayer{Float32}, l), bioclim[1])
landcover = itrp.(landcover)

# Combine the layers
L = [bioclim..., landcover...]
L = [convert(SDMLayer{Float32}, l) for l in L]
for l in L
    l.x = L[1].x
    l.y = L[1].y
end
L = [mask(l, L[end]) for l in L]
SimpleSDMLayers.save("layers.tiff", L)

# Get the data
ouzel = taxon("Turdus torquatus")
presences = occurrences(
    ouzel,
    first(L),
    "occurrenceStatus" => "PRESENT",
    "limit" => 300,
    "datasetKey" => "4fa7b334-ce0d-4e88-aaae-2e0c138d049e",
)
while length(presences) < count(presences)
    occurrences!(presences)
end

# Get the pseudo-absences/presences
presencelayer = zeros(first(L), Bool)
for i in mask(presences, CHE)
    presencelayer[i.longitude, i.latitude] = true
end
background = pseudoabsencemask(DistanceToEvent, presencelayer)
bgpoints = backgroundpoints(nodata(background, d -> d < 6), 2sum(presencelayer))

# Clip and save
occ = mask(presences, CHE)
DelimitedFiles.writedlm("presences.csv", hcat(longitudes.(occ), latitudes.(occ)))

# Names of the layers
lnames = vcat(layers(RasterData(CHELSA2, BioClim)), layers(RasterData(EarthEnv, LandCover)))
DelimitedFiles.writedlm("layernames.csv", lnames)

# Get the layers
prsc = nodata(presencelayer, false)
absc = nodata(bgpoints, false)
SimpleSDMLayers.save("occurrences.tiff", [convert(SDMLayer{Int8}, prsc), convert(SDMLayer{Int8}, absc)])