# Interpolation

This library implements the interpolation methods described here http://paulbourke.net/miscellaneous/interpolation/.

When loaded, the following extension is provided

#### ext-interpolate
```clj
(ext-interpolate value table optMethod)
```

Where value is the x-position in the table, table is the interpolation table and optMethod is an optional argument that specifies the interpolation method to use (by default it uses Catmull-Rom splines).

The available methods are:

0. Linear
1. Cosine
2. Cubic splines
3. Catmull-Rom splines (recommended)

Note: Outside of the table all points are set to the same value as the last point in the table.

## Example

```clj
(import "pkg::interpolation@://vesc_packages/lib_interpolation/interpolation.vescpkg" 'interpolation)

(load-native-lib interpolation)

(def int-tab '(
        (-500.0 90.0)
        (0.0 80.0)
        (500.0 82.0)
        (1000.0 90.0)
        (1500.0 94.0)
        (3000.0 96.0)
        (5000.0 100.0)
))

(ext-interpolate 1220 int-tab 3)
> {92.144386}
```

## Example: Plotting

```clj
(import "pkg::interpolation@://vesc_packages/lib_interpolation/interpolation.vescpkg" 'interpolation)

(load-native-lib interpolation)

(def int-tab '(
        (-500.0 90.0)
        (0.0 80.0)
        (500.0 82.0)
        (1000.0 90.0)
        (1500.0 94.0)
        (3000.0 96.0)
        (5000.0 100.0)
))

(defun plot-range (start end points tab method)
    (looprange i 0 points
        (let (
                (val (+ (* (/ i (to-float points)) (- end start)) start))
            )
            (plot-send-points val (ext-interpolate val tab method))
)))


(def val-start -1000.0)
(def val-end 5500.0)
(def points 500)

(plot-init "Val" "Output")
(plot-add-graph "Linear")
(plot-add-graph "Cosine")
(plot-add-graph "Cubic")
(plot-add-graph "Catmull-Rom")

(plot-set-graph 0)
(plot-range val-start val-end points int-tab 0)

(plot-set-graph 1)
(plot-range val-start val-end points int-tab 1)

(plot-set-graph 2)
(plot-range val-start val-end points int-tab 2)

(plot-set-graph 3)
(plot-range val-start val-end points int-tab 3)
```
