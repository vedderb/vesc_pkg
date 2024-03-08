# Display UI Library

Work-in-progress high-level UI library for the VESC Express display driver.

## Text Module

The text module is self-contained and is imported as follows:

```clj
(import "pkg::disp-text@://vesc_packages/lib_disp_ui/disp_ui.vescpkg" 'disp-text)

(read-eval-program disp-text)
```

### txt-block-c

```clj
(txt-block-c img col cx cy font txt)
```

Create centered text block. Arguments:

| **Name** | **Description**   |
|----------|------------|
| img  | Image Buffer       |
| col  | Color  |
| cx  | Center X |
| cy  | Center Y |
| font  | Font to use |
| text  | Text. Can be a single string or a list of strings. |

Example:

```clj
(import "pkg::disp-text@://vesc_packages/lib_disp_ui/disp_ui.vescpkg" 'disp-text)
(import "pkg::font_16_26@://vesc_packages/lib_files/files.vescpkg" 'font)
(read-eval-program disp-text)

(def img (img-buffer 'indexed2 200 200))
(txt-block-c img 1 100 100 font '("First Line" "Another Line"))
```

## Button Module

Create buttons. Depends on the text module.

```clj
(import "pkg::disp-text@://vesc_packages/lib_disp_ui/disp_ui.vescpkg" 'disp-text)
(import "pkg::disp-button@://vesc_packages/lib_disp_ui/disp_ui.vescpkg" 'disp-button)

(read-eval-program disp-text)
(read-eval-program disp-button)
```

## Symbol Module

Create various symbols. This module is self-contained.

## Gauge Module

Create gauges. Depends on the text module.
