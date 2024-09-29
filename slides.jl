
using SpeciesDistributionToolkit
using CairoMakie
using Statistics
using PrettyTables
using Random
Random.seed!(420)
include("assets/makietheme.jl")


CHE = SpeciesDistributionToolkit.gadm("CHE");
provider = RasterData(CHELSA2, BioClim)
predictors = [
    SDMLayer(
        provider;
        layer = x,
        left = 0.0,
        right = 20.0,
        bottom = 35.0,
        top = 55.0,
    ) for x in 1:19
];
predictors = [trim(mask!(layer, CHE)) for layer in predictors];
predictors = map(l -> convert(SDMLayer{Float32}, l), predictors);


ouzel = taxon("Turdus torquatus")
presences = occurrences(
    ouzel,
    first(predictors),
    "occurrenceStatus" => "PRESENT",
    "limit" => 300,
    "datasetKey" => "4fa7b334-ce0d-4e88-aaae-2e0c138d049e",
)
while length(presences) < count(presences)
    occurrences!(presences)
end


f = Figure(; size=(800, 400))
ax = Axis(f[1,1], aspect=DataAspect())
poly!(ax, CHE.geometry[1], color=:lightgrey)
scatter!(ax, mask(presences, CHE), color=:black)
lines!(ax, CHE.geometry[1]; color = :black)
hidedecorations!(ax)
hidespines!(ax)
current_figure()


presencelayer = zeros(first(predictors), Bool)
for occ in mask(presences, CHE)
    presencelayer[occ.longitude, occ.latitude] = true
end

background = pseudoabsencemask(DistanceToEvent, presencelayer)
bgpoints = backgroundpoints(nodata(background, d -> d < 4), 2sum(presencelayer))


f = Figure(; size=(800, 400))
ax = Axis(f[1,1], aspect=DataAspect())
poly!(ax, CHE.geometry[1], color=:lightgrey)
scatter!(ax, presencelayer; color = :black)
scatter!(ax, bgpoints; color = :red, markersize = 4)
lines!(ax, CHE.geometry[1]; color = :black)
hidedecorations!(ax)
hidespines!(ax)
current_figure()


sdm = SDM(MultivariateTransform{PCA}, NaiveBayes, predictors, presencelayer, bgpoints)


hdr = ["Model", "MCC", "PPV", "NPV", "DOR", "Accuracy"]
tbl = []
for null in [noskill, coinflip, constantpositive, constantnegative]
    m = null(sdm)
    push!(tbl, [null, mcc(m), ppv(m), npv(m), dor(m), accuracy(m)])
end
data = permutedims(hcat(tbl...))
pretty_table(data; backend = Val(:markdown), header = hdr)


folds = kfold(sdm);
cv = crossvalidate(sdm, folds; threshold = false);


hdr = ["Model", "MCC", "PPV", "NPV", "DOR", "Accuracy"]
tbl = []
for null in [noskill, coinflip, constantpositive, constantnegative]
    m = null(sdm)
    push!(tbl, [null, mcc(m), ppv(m), npv(m), dor(m), accuracy(m)])
end
push!(tbl, ["Validation", mean(mcc.(cv.validation)), mean(ppv.(cv.validation)), mean(npv.(cv.validation)), mean(dor.(cv.validation)), mean(accuracy.(cv.validation))])
push!(tbl, ["Training", mean(mcc.(cv.training)), mean(ppv.(cv.training)), mean(npv.(cv.training)), mean(dor.(cv.training)), mean(accuracy.(cv.training))])
data = permutedims(hcat(tbl...))
pretty_table(data; backend = Val(:markdown), header = hdr)


train!(sdm; threshold=false)
prd = predict(sdm, predictors; threshold = false)
current_range = predict(sdm, predictors)


f = Figure(; size = (800, 400))
ax = Axis(f[1, 1]; aspect = DataAspect())
hm = heatmap!(ax, prd; colormap = :linear_worb_100_25_c53_n256, colorrange = (0, 1))
contour!(ax, predict(sdm, predictors); color = :black, linewidth = 0.5)
Colorbar(f[1, 2], hm)
lines!(ax, CHE.geometry[1]; color = :black)
hidedecorations!(ax)
hidespines!(ax)
current_figure()


prsc = nodata(presencelayer, false)
absc = nodata(bgpoints, false)
f = Figure(; size = (800, 400))
ax = Axis(f[1, 1]; aspect = DataAspect())
poly!(ax, CHE.geometry[1], color=:lightgrey)
heatmap!(ax, current_range, colormap=[colorant"#fefefe", colorant"#d4d4d4"])
scatter!(ax, mask(current_range, prsc) .& prsc; markersize=8, strokecolor=:black, strokewidth=1, color=:transparent, marker=:rect)
scatter!(ax, mask(!current_range, prsc) .& prsc; markersize=8, strokecolor=:red, strokewidth=1, color=:transparent, marker=:rect)
scatter!(ax, mask(current_range, absc) .& absc; markersize=8, strokecolor=:red, strokewidth=1, color=:transparent, marker=:hline)
scatter!(ax, mask(!current_range, absc) .& absc; markersize=8, strokecolor=:black, strokewidth=1, color=:transparent, marker=:hline)
lines!(ax, CHE.geometry[1]; color = :black)
hidedecorations!(ax)
hidespines!(ax)
current_figure()


forwardselection!(sdm, folds, [1])


THR = LinRange(0.0, 1.0, 200)
tcv = [crossvalidate(sdm, folds; thr=thr) for thr in THR]
bst = last(findmax([mean(mcc.(c.training)) for c in tcv]))


f= Figure(; size=(400, 400))
ax = Axis(f[1,1])
lines!(ax, THR, [mean(mcc.(c.validation)) for c in tcv], color=:black)
lines!(ax, THR, [mean(mcc.(c.training)) for c in tcv], color=:lightgrey, linestyle=:dash)
scatter!(ax, [THR[bst]], [mean(mcc.(tcv[bst].validation))], color=:black)
xlims!(ax, 0., 1.)
ylims!(ax, 0., 1.)
current_figure()


f= Figure(; size=(400, 400))
ax = Axis(f[1,1])
lines!(ax, [mean(fpr.(c.validation)) for c in tcv], [mean(tpr.(c.validation)) for c in tcv], color=:black)
scatter!(ax, [mean(fpr.(tcv[bst].validation))], [mean(tpr.(tcv[bst].validation))], color=:black)
xlims!(ax, 0., 1.)
ylims!(ax, 0., 1.)
current_figure()


f= Figure(; size=(400, 400))
ax = Axis(f[1,1])
lines!(ax, [mean(ppv.(c.validation)) for c in tcv], [mean(tpr.(c.validation)) for c in tcv], color=:black)
scatter!(ax, [mean(ppv.(tcv[bst].validation))], [mean(tpr.(tcv[bst].validation))], color=:black)
xlims!(ax, 0., 1.)
ylims!(ax, 0., 1.)
current_figure()


cv2 = crossvalidate(sdm, folds; threshold = true)
hdr = ["Model", "MCC", "PPV", "NPV", "DOR", "Accuracy"]
tbl = []
for null in [noskill, coinflip, constantpositive, constantnegative]
    m = null(sdm)
    push!(tbl, [null, mcc(m), ppv(m), npv(m), dor(m), accuracy(m)])
end
push!(tbl, ["Previous", mean(mcc.(cv.validation)), mean(ppv.(cv.validation)), mean(npv.(cv.validation)), mean(dor.(cv.validation)), mean(accuracy.(cv.validation))])
push!(tbl, ["Validation", mean(mcc.(cv2.validation)), mean(ppv.(cv2.validation)), mean(npv.(cv2.validation)), mean(dor.(cv2.validation)), mean(accuracy.(cv2.validation))])
push!(tbl, ["Training", mean(mcc.(cv2.training)), mean(ppv.(cv2.training)), mean(npv.(cv2.training)), mean(dor.(cv2.training)), mean(accuracy.(cv2.training))])
data = permutedims(hcat(tbl...))
pretty_table(data; backend = Val(:markdown), header = hdr)


train!(sdm)
prd = predict(sdm, predictors; threshold = false)
current_range = predict(sdm, predictors)


f = Figure(; size = (800, 400))
ax = Axis(f[1, 1]; aspect = DataAspect())
hm = heatmap!(ax, prd; colormap = :linear_worb_100_25_c53_n256, colorrange = (0, 1))
contour!(ax, predict(sdm, predictors); color = :black, linewidth = 0.5)
Colorbar(f[1, 2], hm)
lines!(ax, CHE.geometry[1]; color = :black)
hidedecorations!(ax)
hidespines!(ax)
current_figure()


prsc = nodata(presencelayer, false)
absc = nodata(bgpoints, false)
f = Figure(; size = (800, 400))
ax = Axis(f[1, 1]; aspect = DataAspect())
poly!(ax, CHE.geometry[1], color=:lightgrey)
heatmap!(ax, current_range, colormap=[colorant"#fefefe", colorant"#d4d4d4"])
scatter!(ax, mask(current_range, prsc) .& prsc; markersize=8, strokecolor=:black, strokewidth=1, color=:transparent, marker=:rect)
scatter!(ax, mask(!current_range, prsc) .& prsc; markersize=8, strokecolor=:red, strokewidth=1, color=:transparent, marker=:rect)
scatter!(ax, mask(current_range, absc) .& absc; markersize=8, strokecolor=:red, strokewidth=1, color=:transparent, marker=:hline)
scatter!(ax, mask(!current_range, absc) .& absc; markersize=8, strokecolor=:black, strokewidth=1, color=:transparent, marker=:hline)
lines!(ax, CHE.geometry[1]; color = :black)
hidedecorations!(ax)
hidespines!(ax)
current_figure()


var_imp = variableimportance(sdm, folds)
var_imp ./= sum(var_imp)

hdr = ["BIO", "Import."]
pretty_table(
    hcat(variables(sdm), var_imp)[sortperm(var_imp; rev=true),:];
    backend = Val(:markdown), header = hdr)


x, y = partialresponse(sdm, 1; threshold=false)
f = Figure(; size=(400, 400))
ax = Axis(f[1,1])
lines!(ax, x, y)
current_figure()


x, y, z = partialresponse(sdm, 1, 10; threshold=false)
f = Figure(; size=(400, 400))
ax = Axis(f[1,1])
heatmap!(ax, x, y, z, colormap=:linear_worb_100_25_c53_n256, colorrange=(0,1))
current_figure()


partial_temp = partialresponse(sdm, predictors, 1; threshold=false)
f = Figure(; size = (800, 400))
ax = Axis(f[1, 1]; aspect = DataAspect())
hm = heatmap!(ax, partial_temp; colormap = :linear_wcmr_100_45_c42_n256, colorrange = (0, 1))
contour!(ax, predict(sdm, predictors); color = :black, linewidth = 0.5)
Colorbar(f[1, 2], hm)
lines!(ax, CHE.geometry[1]; color = :black)
hidedecorations!(ax)
hidespines!(ax)
current_figure()


partial_temp = partialresponse(sdm, predictors, 1; threshold=true)
f = Figure(; size = (800, 400))
ax = Axis(f[1, 1]; aspect = DataAspect())
hm = heatmap!(ax, partial_temp; colormap = :linear_wcmr_100_45_c42_n256, colorrange = (0, 1))
contour!(ax, predict(sdm, predictors); color = :black, linewidth = 0.5)
Colorbar(f[1, 2], hm)
lines!(ax, CHE.geometry[1]; color = :black)
hidedecorations!(ax)
hidespines!(ax)
current_figure()


f = Figure(; size=(400, 400))
ax = Axis(f[1,1])
for i in 1:300
    lines!(ax, partialresponse(sdm, 1; inflated=true, threshold=false)..., color=:lightgrey, alpha=0.5)
end
lines!(ax, partialresponse(sdm, 1; inflated=false, threshold=false)..., color=:black)
ylims!(ax, 0., 1.)
xlims!(ax, extrema(features(sdm, 1))...)
current_figure()


explain(sdm, 1; threshold=false)


f = Figure(; size=(800, 400))
ax = Axis(f[1,1])
hexbin!(ax, features(sdm, 1), explain(sdm, 1; threshold=false), bins=60, colormap=:linear_bgyw_15_100_c68_n256)
ax2 = Axis(f[1,2])
hist!(ax2, explain(sdm, 1; threshold=false), color=:lightgrey, strokecolor=:black, strokewidth=1)
current_figure()


shapley_temp = explain(sdm, predictors, 1; threshold=false)
f = Figure(; size = (800, 400))
ax = Axis(f[1, 1]; aspect = DataAspect())
hm = heatmap!(ax, shapley_temp; colormap = :diverging_bwg_20_95_c41_n256, colorrange = (-0.2, 0.2))
contour!(ax, predict(sdm, predictors); color = :black, linewidth = 0.5)
Colorbar(f[1, 2], hm)
lines!(ax, CHE.geometry[1]; color = :black)
hidedecorations!(ax)
hidespines!(ax)
current_figure()


S = [explain(sdm, predictors, v; threshold=false) for v in variables(sdm)]
shap_imp = map(x -> sum(abs.(x)), S)
shap_imp ./= sum(shap_imp)
most_imp = mosaic(x -> argmax(abs.(x)), S)
hdr = ["BIO", "Import.", "Shap. imp."]
pretty_table(
    hcat(variables(sdm), var_imp, shap_imp)[sortperm(shap_imp; rev=true),:];
    backend = Val(:markdown), header = hdr)


f = Figure(; size = (800, 400))
ax = Axis(f[1, 1]; aspect = DataAspect())
hm = heatmap!(ax, most_imp; colormap = :glasbey_bw_n256)
contour!(ax, predict(sdm, predictors); color = :black, linewidth = 0.5)
lines!(ax, CHE.geometry[1]; color = :black)
hidedecorations!(ax)
hidespines!(ax)
current_figure()


luprovider = RasterData(EarthEnv, LandCover)
landcover = [
    SDMLayer(
        luprovider;
        layer = x,
        left = 0.0,
        right = 20.0,
        bottom = 35.0,
        top = 55.0,
    ) for x in 1:12
];
landcover = [trim(mask!(layer, CHE)) for layer in landcover];
landcover = map(l -> convert(SDMLayer{Float32}, l), landcover);
prsl = zeros(landcover[1], Bool)
absl = zeros(landcover[1], Bool)
prct = SimpleSDMLayers._centers(prsc)
abct = SimpleSDMLayers._centers(absc)
for i in axes(prct, 2)
    prsl[prct[:,i]...] = true
end
for i in axes(abct, 2)
    absl[abct[:,i]...] = true
end
rtree = SDM(MultivariateTransform{PCA}, DecisionTree, landcover, prsl, absl)


forest = Bagging(rtree, 10)
train!(forest)

