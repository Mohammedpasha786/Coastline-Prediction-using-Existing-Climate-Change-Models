# Coastline Prediction using Existing Climate Change Models

> **MATLAB project** | Mapping Toolbox · Image Processing Toolbox  
> Motivation from NOAA: average global sea level rose **2.6 inches** between 1993 and 2014, and rising levels threaten coastal infrastructure worldwide.

## Overview

This project provides a complete MATLAB framework to:

| Step | What it does |
|------|-------------|
| **Download elevation data** | Pull 1/3 or 1 arc-second DEMs from the USGS National Map (3DEP) |
| **Fetch SLR projections** | Query NOAA CO-OPS tide-gauge projections or Copernicus CDS CMIP6 data |
| **Predict new coastlines** | Compute inundation masks and coastline boundaries for any SLR value |
| **Visualize** | Render a hillshaded terrain map with flood overlays and labelled coastline paths |
| **Interactive app** | Point-and-click MATLAB App Designer interface for non-programmers |

---

## Project Structure

```
coastline_prediction/
├── src/
│   ├── predictCoastline.m      ← Core inundation + coastline function
│   ├── visualizeCoastline.m    ← Map rendering with flood overlays
│   ├── fetchClimateSealevel.m  ← NOAA / Copernicus SLR data fetcher
│   └── downloadUSGSDEM.m       ← USGS 3DEP DEM downloader
├── examples/
│   └── example_miami_projection.m   ← Full 100-year Miami case study
├── app/
│   └── CoastlineExplorer.m     ← Interactive MATLAB App
├── tests/
│   └── test_predictCoastline.m ← matlab.unittest test suite
├── data/                        ← Cached tiles (git-ignored)
├── output/                      ← Exported figures
└── docs/
    └── methodology.md
```

---

## Requirements

| Item | Minimum version |
|------|----------------|
| MATLAB | R2021b |
| Mapping Toolbox | any version bundled with MATLAB |
| Image Processing Toolbox | any version bundled with MATLAB |
| Internet access | Required for initial data downloads |

Optional for Copernicus CDS backend:  
- A free CDS account and API key from [cds.climate.copernicus.eu](https://cds.climate.copernicus.eu)

---

## Quick Start

```matlab
% 1. Clone / download the repo and open MATLAB in the project root.

% 2. Run the Miami example (downloads data on first run, ~50 MB):
run('examples/example_miami_projection.m')

% 3. Launch the interactive app:
CoastlineExplorer()
```

---

## Core Functions

### `predictCoastline`

```matlab
[newCoast, floodedArea, stats] = predictCoastline(dem, R, seaLevelRise)
[newCoast, floodedArea, stats] = predictCoastline(dem, R, seaLevelRise, Name, Value)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `dem` | double matrix | Digital Elevation Model in metres above current MSL |
| `R` | `georasterref` | Raster reference matching the DEM |
| `seaLevelRise` | scalar | Sea-level rise in metres (positive) |
| `'BaselineElevation'` | scalar | Current sea level in the DEM (default: 0 m) |
| `'ConnectedOcean'` | logical | Only flood cells reachable from the ocean (default: true) |
| `'SmoothCoastline'` | logical | Morphological smoothing of the boundary (default: true) |
| `'PopulationGrid'` | matrix | Population density (persons/km²) for displacement stats |

**Returns:**
- `newCoast` – Nx2 `[lat lon]` array of coastline vertices (NaN-separated segments)
- `floodedArea` – binary mask of newly inundated cells
- `stats` – struct with `.floodedCells`, `.floodedAreaKm2`, `.displacedPopulation`

---

### `fetchClimateSealevel`

```matlab
[years, sealevel_m, metadata] = fetchClimateSealevel(lat, lon)
[years, sealevel_m, metadata] = fetchClimateSealevel(lat, lon, Name, Value)
```

| Parameter | Options | Description |
|-----------|---------|-------------|
| `'Source'` | `'NOAA'` \| `'Copernicus'` | Data provider |
| `'Scenario'` | `'low'` \| `'intermediate'` \| `'high'` | Emissions scenario |
| `'YearRange'` | `[start end]` | Year range (default: 2020–2150) |

Returns annual projections in metres above the 2000 baseline.  
Falls back to IPCC AR6 synthetic curves if network access fails.

---

### `downloadUSGSDEM`

```matlab
[dem, R] = downloadUSGSDEM(latLim, lonLim)
[dem, R] = downloadUSGSDEM(latLim, lonLim, 'Resolution', 1)   % 1 arc-sec
```

Downloads and caches USGS 3DEP elevation tiles for any contiguous US bounding box.

---

### `visualizeCoastline`

```matlab
fig = visualizeCoastline(dem, R, coastlines, labels)
fig = visualizeCoastline(dem, R, coastlines, labels, 'FloodMasks', masks, ...)
```

Renders hillshaded terrain with semi-transparent flood overlays and labelled coastline polylines. Accepts multiple coastlines for side-by-side scenario comparison.

---

## Data Sources

| Source | Data type | Resolution | Coverage |
|--------|-----------|------------|----------|
| [USGS National Map (3DEP)](https://apps.nationalmap.gov/) | Elevation (DEM) | 1/9, 1/3, 1 arc-sec | Continental US |
| [NOAA CO-OPS](https://tidesandcurrents.noaa.gov/) | Tide gauge SLR projections | Gauge point | US coastlines |
| [Copernicus CDS](https://cds.climate.copernicus.eu/) | CMIP6 sea-level projections | ~1° grid | Global |
| [NOAA Digital Coast](https://coast.noaa.gov/digitalcoast/) | Lidar, imagery, flood data | Varies | US coastlines |

---

## Interactive App

Launch `CoastlineExplorer` from the MATLAB command window:

```matlab
CoastlineExplorer()
```

Features:
- **Slider + spinner** to select any year between 2024 and 2200
- **Dropdown** for Low / Intermediate / High emissions scenario
- **Manual override** to enter a specific SLR value in metres
- **Bounding-box spinners** to define the study region
- **Compute button** triggers automatic DEM download, SLR fetch, and coastline prediction
- **Export PNG** saves the current map view at 200 dpi

---

## Running the Tests

```matlab
cd tests
results = runtests('test_predictCoastline');
table(results)
```

The suite covers:
- Output dimensions and types
- Zero-rise produces zero flooded cells
- Flood area is monotonically non-decreasing with SLR
- Connected-ocean mask correctly excludes isolated inland basins
- Population displacement statistics
- Invalid input rejection

---

## Results: Miami Case Study

Running `example_miami_projection.m` with the **High (RCP8.5)** scenario produces approximate inundation figures:

| Year | SLR (m) | Flooded area |
|------|---------|-------------|
| 2050 | ~0.25 m | ~18 km² |
| 2075 | ~0.60 m | ~52 km² |
| 2124 | ~1.40 m | ~180 km² |

*(Figures are illustrative; exact values depend on the NOAA station projection and DEM resolution.)*

---

## Extending the Project

### New flood-impact metrics
- **Road/bridge network disruption** – intersect flood mask with OpenStreetMap road vectors (`osm2matlab` or MATLAB's `shaperead`)
- **Property value at risk** – join flood mask with county parcel data (CSV or shapefile)
- **Storm-surge compounding** – add a surge layer (NOAA SLOSH model) on top of SLR

### Additional regions
Pass different `latLim` / `lonLim` to `downloadUSGSDEM`. For non-US regions use the **Copernicus GLO-30** DEM (30 m, global):
```matlab
% Example wrapper (Copernicus GLO-30 via OpenTopography API)
[dem, R] = downloadGLO30DEM(latLim, lonLim, 'APIKey', 'YOUR_KEY');
```

### Model uncertainty bands
`fetchClimateSealevel` returns only the median. Extend it to also return the 5th/95th percentile from NOAA's probability curves and visualize confidence bands.

### Real-time NOAA water-level overlay
NOAA provides observed water-level data at 6-minute intervals. Overlay live data on the map using a `timer` object that polls the API every few minutes.

---

## References

1. IPCC AR6 Working Group I (2021). *The Physical Science Basis.* Sea-level chapter.
2. Sweet, W.V., et al. (2022). *2022 Sea Level Rise Technical Report.* NOAA.
3. USGS National Map – 3DEP: https://www.usgs.gov/3d-elevation-program
4. Copernicus CDS – CMIP6 SLR: https://cds.climate.copernicus.eu
5. NOAA CO-OPS Tide Gauge Projections: https://tidesandcurrents.noaa.gov/sltrends/
6. NOAA Sea Level Rise Viewer: https://coast.noaa.gov/slr/
