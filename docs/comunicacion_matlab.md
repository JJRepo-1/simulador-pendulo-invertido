# Comunicación Godot ↔ MATLAB (modo batch)

Este documento describe cómo la plataforma calcula las ganancias del controlador (K para la regulación y Ka para el seguimiento de trayectoria) llamando a MATLAB con YALMIP y SeDuMi.

## 1. Idea general

Godot **no se conecta** a una sesión de MATLAB. Lo que hace es:

1. escribir los datos en un archivo JSON,
2. ejecutar MATLAB como un programa externo, sin ventana (`-batch`),
3. esperar a que termine,
4. leer la respuesta en otro archivo JSON.

Es una comunicación **por archivos**, en una sola dirección por llamada: petición y luego respuesta. Cada cálculo abre y cierra MATLAB.

```
 Godot (Configuración)                         MATLAB (proceso externo)
 ─────────────────────                         ────────────────────────
 [Calcular K] ─► advertencia (Aceptar)
              ─► escribe entrada.json
              ─► copia calcular_ganancias.m
              ─► lanza matlab.exe -batch ... ───►  lee entrada.json
                 (ventana de progreso,             resuelve el LMI (YALMIP + SeDuMi)
                  revisa cada frame si             calcula los polos
                  el proceso sigue vivo)           escribe salida.json
              ◄── el proceso termina ◄─────────── sale
              ─► lee salida.json
              ─► muestra el resultado y copia K a los spinboxes
```

## 2. Archivos involucrados

| Archivo | Rol |
|---|---|
| `calculo_matlab.gd` (clase `CalculoMatlab`) | Ventanas, detección de MATLAB, escritura y lectura de JSON, lanzamiento y monitoreo del proceso |
| `matlab/calcular_ganancias.m` | Función de MATLAB que resuelve el LMI |
| `configuracion.gd` | Botón "Calcular K con MATLAB" (regulación) y aplicación del resultado |
| `editor_aumentado.gd` | Botón "Calcular Ka con MATLAB" (seguimiento), mediante la señal `calcular_con_matlab` |

**Carpeta de trabajo:** `user://matlab`. En Windows es `%APPDATA%\Godot\app_userdata\Pendulo\matlab\` y contiene:

- `calcular_ganancias.m`: se copia desde el proyecto en cada cálculo.
- `entrada.json`: la escribe Godot.
- `salida.json`: la escribe MATLAB; Godot la borra antes de cada cálculo.

**Ajustes guardados:** `user://ajustes.cfg`, sección `[matlab]`, clave `ruta`, con la ruta de `matlab.exe`.

## 3. Flujo paso a paso

### Paso 1. El usuario presiona un botón

| Botón | Sistema | Matrices que se envían | α / β por defecto |
|---|---|---|---|
| "Calcular K con MATLAB" | Regulación (`codigo4.m`) | A (4×4) y B (4×1) de la **pestaña 2** | 2 / 10 |
| "Calcular Ka con MATLAB" | Seguimiento (`codigo_seguimiento.m`) | Aa (5×5) y Ba (5×1) de la **pestaña 3** | 1 / 10 |

Las matrices se mandan **ya evaluadas numéricamente** con los parámetros que hay en pantalla. Así el LMI se resuelve con el modelo lineal que escribió el estudiante, no con uno fijo. Si esas fórmulas tienen errores, el cálculo no se inicia y se pide corregirlas.

### Paso 2. Advertencia y opciones

La ventana muestra:

- el aviso de que se necesita MATLAB con YALMIP y SeDuMi en su path;
- α y β, que definen la región de polos −β ≤ Re(p) ≤ −α;
- la ruta de `matlab.exe`.

Godot busca la ruta en este orden:

1. la ruta guardada en `ajustes.cfg`;
2. el PATH del sistema (`where matlab` en Windows, `which matlab` en Linux y macOS);
3. las carpetas habituales (`C:/Program Files/MATLAB/<versión>/bin/matlab.exe`), tomando la versión más reciente.

Al presionar **Aceptar** se valida que la ruta exista y que β > α, y la ruta se guarda para la próxima vez.

### Paso 3. Preparación de archivos

- Se copia `res://matlab/calcular_ganancias.m` a la carpeta de trabajo. Esto es necesario porque, en el juego exportado, `res://` va empaquetado y MATLAB no puede leerlo.
- Se escribe `entrada.json`:

```json
{
  "A": [[0, 0, 1, 0],
        [0, 0, 0, 1],
        [0, -0.4671, 0, 0],
        [0, 10.2771, 0, 0]],
  "B": [0, 0, 0.4762, -0.4762],
  "alpha": 2.0,
  "beta": 10.0,
  "ts": 0.001
}
```

### Paso 4. Lanzamiento de MATLAB

```
matlab.exe -wait -batch "addpath('<carpeta>'); calcular_ganancias('<carpeta>/entrada.json','<carpeta>/salida.json')"
```

- `-batch` ejecuta el comando sin interfaz gráfica y cierra MATLAB al terminar.
- `-wait` solo se usa en Windows: hace que el lanzador espere a MATLAB, y así Godot puede saber cuándo terminó.
- Se usa `OS.create_process()`, que **no bloquea**: la aplicación sigue respondiendo mientras MATLAB calcula.

### Paso 5. Espera y monitoreo

- En cada frame, Godot revisa `OS.is_process_running(pid)` y actualiza la ventana "Calculando con MATLAB… N s".
- **Cancelar cálculo** termina el proceso con `OS.kill(pid)`.
- Si pasan más de **300 s**, el proceso se termina automáticamente.
- Si el usuario sale de Configuración mientras se calcula, el proceso también se termina.

### Paso 6. Qué hace `calcular_ganancias.m`

1. Lee `entrada.json` con `jsondecode`.
2. Revisa que A sea n×n y que B tenga n elementos.
3. Revisa que estén YALMIP (`sdpvar`) y SeDuMi (`sedumi`).
4. Revisa la controlabilidad: el rango de [B AB … Aⁿ⁻¹B] debe ser n.
5. Resuelve el LMI, igual que en los scripts del curso:

   ```
   Q ≥ I,   L + Lᵀ ≤ −2αQ,   L + Lᵀ ≥ −2βQ,   L = AQ − BY
   ```

6. Revisa que Q y Y sean finitas y que Q no sea casi singular (`rcond`).
7. Calcula K = Y/Q, los polos de A − BK y los polos discretos con Euler.
8. Escribe `salida.json` con `jsonencode`.

Todo va dentro de un `try/catch`: **siempre** se escribe `salida.json`, aunque haya error. Así Godot nunca se queda esperando una respuesta que no llega.

### Paso 7. Respuesta (`salida.json`)

```json
{
  "ok": true,
  "error": "",
  "K": [-86.9937, -340.2803, -77.5246, -104.9065],
  "polos_re": [-4.111, -4.111, -2.408, -2.408],
  "polos_im": [6.894, -6.894, 0.713, -0.713],
  "polos_euler_abs": [0.9959, 0.9959, 0.9976, 0.9976],
  "info": "Successfully solved (SeDuMi-1.3)"
}
```

Si hay un error: `"ok": false` y `"error"` contiene el mensaje de MATLAB, por ejemplo "No se encontró SeDuMi en el path".

### Paso 8. Interpretación en Godot

- Se revisa que K tenga n valores.
- Se muestran K, los polos y una evaluación:
  - si son estables y cumplen la región −β ≤ Re(p) ≤ −α;
  - el estado de SeDuMi (`info`), con una advertencia si no dice "Successfully".
- Los valores se copian a los spinboxes: K1–K4 en la columna izquierda, o Ka1–Ka5 en la pestaña 3.
- Las ganancias **no se usan en la simulación hasta presionar "Guardar datos"**, que las pasa a `Globals`.

## 4. Manejo de errores

| Situación | Qué ve el usuario |
|---|---|
| Fórmulas de A/B o Aa/Ba con errores | Aviso "Corrige A y B…"; no se lanza MATLAB |
| Ruta de MATLAB inválida | "No se encontró MATLAB en: …" |
| MATLAB no arranca | "No se pudo iniciar MATLAB" |
| Falta YALMIP o SeDuMi, sistema no controlable o LMI no confiable | El mensaje de error que devuelve MATLAB |
| MATLAB termina sin `salida.json` (por ejemplo, sin licencia) | Indicaciones y la carpeta de trabajo para probar la función a mano |
| Más de 300 s | Se cancela automáticamente |
| SeDuMi reporta problemas numéricos | Se muestran las ganancias con una advertencia para revisar los polos |

## 5. Requisitos y limitaciones

- **Requisitos:** MATLAB instalado con licencia activa, y YALMIP y SeDuMi en el path (`addpath(genpath(...))` y `savepath`).
- **Tiempo:** cada cálculo tarda entre 10 y 20 s, sobre todo por el arranque de MATLAB.
- **Exportación:** en el preset de exportación hay que agregar `*.m` en "Filters to export non-resource files"; si no, el archivo de MATLAB no se incluye.
- **Plan B:** si no hay MATLAB, la aplicación funciona igual escribiendo las ganancias a mano.
- **Sistemas operativos:** funciona en Windows, Linux y macOS. Solo cambian la detección de la ruta y el uso de `-wait`.
