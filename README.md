# Simulador de Péndulo Invertido

Plataforma didáctica **gratuita y sin fines de lucro** para aprender control automático con el clásico péndulo invertido sobre un carro. Corre en computadoras modestas: no necesitas un equipo potente ni licencias de software para simular.

Los estudiantes escriben **sus propias ecuaciones** (modelo no lineal y matrices A, B), y la plataforma las revisa, las simula en tiempo real y compara el sistema "real" contra su modelo lineal. Así se recorre el mismo camino que en un curso de control:

**sistema no lineal sin control → linealización → control por realimentación de estados → seguimiento de trayectoria con acción integral**

Hecho con [Godot Engine](https://godotengine.org) 4.7.

---

## Contenido

- [Descarga y uso rápido](#descarga-y-uso-rápido)
- [Qué incluye](#qué-incluye)
- [Cómo se usa](#cómo-se-usa)
- [Modelo físico](#modelo-físico)
- [Cálculo de ganancias con MATLAB (opcional)](#cálculo-de-ganancias-con-matlab-opcional)
- [Abrir el proyecto en Godot](#abrir-el-proyecto-en-godot)
- [Estructura del proyecto](#estructura-del-proyecto)
- [Artículo asociado](#artículo-asociado)
- [Licencia](#licencia)
- [Créditos y licencias de terceros](#créditos-y-licencias-de-terceros)
- [Aviso](#aviso)

---

## Descarga y uso rápido

1. Entra a la sección [**Releases**](https://github.com/JJRepo-1/simulador-pendulo-invertido/releases) del repositorio.
2. Descarga el ejecutable de la versión más reciente (Windows).
3. Ábrelo. No requiere instalación.

## Qué incluye

| Simulación | Descripción |
|---|---|
| **Péndulo sin control** | El modelo no lineal con u = 0: se observa cómo cae el péndulo desde un ángulo inicial. |
| **Péndulo con control (regulación)** | Realimentación de estados u = −K·X que lleva el sistema al equilibrio desde una posición y un ángulo iniciales. Compara en vivo el modelo no lineal contra el lineal. |
| **Seguimiento de trayectoria** | Sistema aumentado con acción integral (z' = r − x), u = −Ka·Xa. Se cambia la referencia de posición en escalón y el integrador elimina el error en estado estacionario. |

Además:

- **Ecuaciones editables.** Se escriben tal como salen de Euler-Lagrange, por ejemplo
  `(M+m)*x''+m*l*θ''*cosθ-m*l*θ'^2*senθ = u`.
  La plataforma despeja x'' y θ'' por sí sola y avisa de errores de escritura, ecuaciones no lineales en las aceleraciones o sistemas que no se pueden resolver.
- **Revisión de A y B celda por celda.** Cada término se compara contra la linealización numérica de las ecuaciones del estudiante: verde = correcto, naranja = no coincide, rojo = error de escritura.
- **Polos de lazo cerrado** calculados al instante, equivalentes a `eig(A − B*K)` de MATLAB.
- **Gráficas** de x, θ, x' y θ' con ejes de tiempo y unidades, y comparación contra el modelo lineal.
- **Tiempo de simulación configurable**, para comparar las gráficas con las de MATLAB.
- **Sistema ideal o con fricción** viscosa en el carro (c) y en el pivote (b).
- **Saturación del actuador** y límites físicos de la pista.

## Cómo se usa

### 1. Configuración

En el menú principal entra a **Configuración**:

- **Columna izquierda:** parámetros físicos (M, m, l, J, c, b), fuerza máxima del actuador y ganancias K1–K4 del regulador.
- **Pestaña 1 · Modelo no lineal:** las dos ecuaciones de movimiento (dinámica del carro y del péndulo). Los botones θ, θ' y θ'' insertan los símbolos que no están en el teclado.
- **Pestaña 2 · Modelo lineal (A, B):** las matrices del modelo linealizado escritas como fórmulas de los parámetros (por ejemplo `-(m^2*g*l^2)/Delta`).
- **Pestaña 3 · Seguimiento (Aa, Ba, Ka):** el sistema aumentado para la acción integral, las ganancias Ka y sus polos.

Presiona **Guardar datos** para que las simulaciones usen los cambios.

### 2. Simulaciones

- Asigna la posición inicial, el ángulo inicial y el tiempo de simulación, y presiona **Simular**.
- **Mostrar gráficas** abre un panel con una gráfica a la vez; los botones ◀ ▶ cambian entre x, θ, x' y θ'.
- La casilla **Comparar con modelo lineal** dibuja un péndulo "fantasma" rosa con la predicción del modelo lineal.
- Con ángulos iniciales de más de 30° aparece una advertencia: el péndulo sale de la zona donde el modelo lineal es válido.
- En el seguimiento de trayectoria, escribe la **referencia de posición** y presiona **Aceptar referencia**.

### Notación de las fórmulas

| Escribe | Significa |
|---|---|
| `x`, `θ` (o `theta`) | posición del carro y ángulo (θ = 0 es el péndulo hacia arriba) |
| `x'`, `θ'` | velocidades |
| `x''`, `θ''` | aceleraciones |
| `u` | fuerza sobre el carro |
| `M m l J g c b` | parámetros físicos |
| `+ - * / ^ ( )` | operadores (`^` es potencia, como en MATLAB) |
| `sen sin cos tan sqrt exp log abs pow min max` | funciones (`senθ` y `cosθ` sin paréntesis también valen) |
| `pi` | constante π |

## Modelo físico

Estado X = [x, θ, x', θ'], con θ medido desde la vertical superior. Ecuaciones del sistema ideal:

```
(M + m)·x'' + m·l·θ''·cos θ − m·l·θ'²·sen θ = u
(J + m·l²)·θ'' + m·l·x''·cos θ − m·g·l·sen θ = 0
```

Valores por defecto: M = 2 kg, m = 0.2 kg, l = 0.5 m, J = 0.05 kg·m², g = 9.81 m/s².

Linealización en X = 0, con Δ = (M + m)·J + M·m·l²:

```
A = [ 0          0           1  0 ]      B = [ 0            ]
    [ 0          0           0  1 ]          [ 0            ]
    [ 0   −m²·g·l²/Δ         0  0 ]          [ (J + m·l²)/Δ ]
    [ 0   (M + m)·m·g·l/Δ    0  0 ]          [ −m·l/Δ       ]
```

Las ganancias por defecto se obtuvieron en MATLAB con un LMI de región de polos (YALMIP + SeDuMi):

- Regulador (α = 2, β = 10): K = [−86.9937, −340.2803, −77.5246, −104.9065]
- Seguimiento con acción integral (α = 1, β = 10): Ka = [−85.5197, −277.5251, −60.9428, −85.1777, 52.7022]

La simulación integra las ecuaciones con Runge-Kutta de 4º orden (paso máximo de 1/240 s).

## Cálculo de ganancias con MATLAB (opcional)

Si tienes **MATLAB** con **YALMIP** y **SeDuMi** en su path, los botones **Calcular K con MATLAB** y **Calcular Ka con MATLAB** resuelven el LMI con las matrices que escribiste y copian las ganancias a la pantalla.

- La plataforma abre MATLAB en segundo plano (`matlab -batch`) e intercambia datos mediante archivos JSON. Cada cálculo tarda entre 10 y 20 s.
- La ruta de MATLAB se detecta sola y se puede cambiar en la ventana de confirmación, junto con α y β.
- La función de MATLAB está en [`matlab/calcular_ganancias.m`](matlab/calcular_ganancias.m) y también se puede usar por separado.

**Sin MATLAB la plataforma funciona igual:** las ganancias se escriben a mano en Configuración.

Para instalar las herramientas en MATLAB:

```matlab
addpath(genpath('C:\ruta\a\YALMIP'));
addpath(genpath('C:\ruta\a\sedumi'));
savepath
```

## Abrir el proyecto en Godot

1. Descarga [Godot 4.7](https://godotengine.org/download) (versión estándar, no .NET).
2. Clona o descarga este repositorio.
3. En Godot: **Importar** → selecciona `project.godot`.
4. Presiona **F5** para ejecutar.

Para exportar el ejecutable usa el preset **Windows Desktop** (Proyecto → Exportar). Ya incluye los archivos `*.m`, necesarios para el cálculo con MATLAB.

## Estructura del proyecto

| Archivo | Contenido |
|---|---|
| `main.tscn` | Menú principal |
| `configuracion.tscn` / `.gd` | Pantalla de configuración |
| `editor_modelo_lineal.gd` | Pestañas 1 y 2: ecuaciones no lineales y matrices A, B |
| `editor_aumentado.gd` | Pestaña 3: Aa, Ba, Ka y polos |
| `formulas_lineales.gd` | Compilador de fórmulas (notación θ, x', θ'', sen, `^`...) |
| `modelo_formulas.gd` | Modelo no lineal a partir de las ecuaciones del estudiante |
| `modelo_pendulo.gd` | Modelo de referencia y linealización numérica |
| `algebra.gd` | Polos de lazo cerrado (polinomio característico y raíces) |
| `pendulo.tscn` / `pendulo.gd` | Péndulo sin control |
| `pendulo2.tscn` / `pendulo_2.gd` | Péndulo con control (regulación) |
| `pendulo3.tscn` / `pendulo_3.gd` | Seguimiento de trayectoria con acción integral |
| `panel_graficas.gd`, `graficas.gd` | Panel y gráficas en tiempo real |
| `control_tiempo.gd` | Tiempo de simulación |
| `calculo_matlab.gd` | Comunicación con MATLAB en modo batch |
| `matlab/calcular_ganancias.m` | LMI de región de polos con YALMIP + SeDuMi |
| `Globals.gd` | Parámetros, ecuaciones y ganancias compartidos entre pantallas |

## Artículo asociado

Esta plataforma forma parte del trabajo de investigación:

> Josue Jordan Ramos Sanchez, Ernesto Imanol Ramírez Hernández y Jesús Salvador Martínez Farías.
> *Desarrollo de una herramienta educativa para simular un péndulo invertido con carrito mediante Godot y MATLAB.*
> En preparación, 2026.

**Colaboradores en la investigación:** Ernesto Imanol Ramírez Hernández y Jesús Salvador Martínez Farías.

Si usas esta herramienta en un trabajo académico, cita el artículo (los datos de publicación se agregarán aquí cuando esté disponible) y este repositorio.

## Licencia

**© 2026 Josue Jordan Ramos Sanchez.**

Esta obra está bajo la licencia [Creative Commons Atribución-NoComercial-CompartirIgual 4.0 Internacional (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.es). El texto completo está en [`LICENSE`](LICENSE).

**Puedes:**

- **Usarla** en clases, cursos, tareas y proyectos escolares.
- **Compartirla:** copiarla y redistribuirla.
- **Modificarla** y crear versiones propias.

**Siempre que:**

- **Atribución:** des crédito al autor original, enlaces a la licencia e indiques si hiciste cambios.
- **No comercial:** no la uses con fines comerciales, ni el original ni las versiones modificadas. No se puede vender, cobrar por ella ni incluir en productos o servicios de pago.
- **Compartir igual:** si la modificas, publiques tu versión con esta misma licencia.

## Créditos y licencias de terceros

- **Autor:** Josue Jordan Ramos Sanchez, como proyecto de maestría.
- **[Godot Engine](https://godotengine.org)**, © Juan Linietsky, Ariel Manzur y colaboradores, bajo [licencia MIT](https://godotengine.org/license). Los ejecutables exportados incluyen el motor. Sus avisos de licencia, y los de los componentes de terceros que trae, están en la pantalla **Créditos y licencias** del menú principal y en [`LICENCIAS.txt`](LICENCIAS.txt), que acompaña cada Release.
- **Logo de Godot** (`icon.svg`, usado en el menú principal), de Andrea Calabró, bajo [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
- **MATLAB** es marca registrada de The MathWorks, Inc. **YALMIP** (Johan Löfberg) y **SeDuMi** son herramientas externas: **no se incluyen** en este proyecto, solo se usan si el usuario ya las tiene instaladas.

## Aviso

Esta es una **herramienta educativa**. Se proporciona "tal cual", sin garantía de ningún tipo. Los modelos y controladores son simplificados para fines de aprendizaje y **no deben usarse para controlar sistemas físicos reales**.
