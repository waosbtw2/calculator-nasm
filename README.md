# NASM x86_64

## 1. Requisitos

| Herramienta | Para qué sirve |
|---|---|
| `nasm` | Ensamblador: convierte `main.asm` en código máquina (`main.o`) |
| `gcc` | Se usa como *enlazador*: une `main.o` con libX11, libc y el código de arranque |
| libX11 (cabeceras y biblioteca) | Funciones de X11 (`XOpenDisplay`, `XDrawString`, ...) |
| Un servidor X | Xorg, o XWayland si usas Wayland (la variable `DISPLAY` debe existir) |

Instalación de libX11 según la distribución:

```bash
# Debian / Ubuntu
sudo apt install nasm gcc libx11-dev
# Arch
sudo pacman -S nasm gcc libx11
# Gentoo
sudo emerge dev-lang/nasm x11-libs/libX11
```

---

## 2. Compilar y ejecutar

```bash
nasm -f elf64 main.asm -o main.o
gcc -no-pie main.o -o calc -lX11
./calc
```

### Qué hace cada comando y cada parámetro

#### `nasm -f elf64 main.asm -o main.o`

| Parte | Significado |
|---|---|
| `nasm` | Invoca el ensamblador. |
| `-f elf64` | **f**ormato de salida: ELF de 64 bits, el formato de objetos de Linux x86_64. Otras opciones serían `elf32`, `win64`, `macho64`... |
| `main.asm` | Archivo fuente de entrada. |
| `-o main.o` | **o**utput: nombre del archivo objeto generado. Un `.o` todavía no es ejecutable: le faltan las funciones de X11 y el punto de entrada. |

#### `gcc -no-pie main.o -o calc -lX11`

| Parte | Significado |
|---|---|
| `gcc` | Aquí no compila C: solo llama al enlazador `ld` con las rutas y bibliotecas correctas (libc, `crt1.o`, etc.). Es más cómodo que llamar a `ld` a mano. |
| `-no-pie` | Genera un ejecutable **no** independiente de la posición (cargado en una dirección fija). Evita problemas de reubicación con código ensamblador escrito a mano. Este programa usa direccionamiento relativo (`default rel`) y `wrt ..plt`, así que probablemente también funcionaría sin esta opción, pero se deja por seguridad. |
| `main.o` | Archivo objeto que se va a enlazar. |
| `-o calc` | Nombre del ejecutable final. |
| `-lX11` | Enlaza con `libX11.so` (la `-l` se escribe pegada al nombre de la biblioteca, sin el prefijo `lib`). Sin esto aparecerían errores de "undefined reference to XOpenDisplay". |

> **Por qué la función se llama `main` y no `_start`:** al enlazar con `gcc`, el código de arranque de libc (`crt1.o`) ya define `_start`, prepara el entorno y llama a `main`. Cuando `main` hace `ret`, el valor de `eax` es el código de salida del programa.

---

## 3. Uso

| Entrada | Acción |
|---|---|
| Clic izquierdo en un botón | Pulsa ese botón |
| `0`-`9` | Escribe dígitos |
| `+` `-` `*` `/` | Operaciones (también `x` para multiplicar) |
| `Enter` o `=` | Calcula el resultado |
| `c` | Limpia todo (equivale al botón `C`) |
| `Backspace` | Borra el último dígito |
| `q` o `Esc` | Sale |
| Botón X de la ventana | Sale |

Limitaciones: solo enteros (la división es entera, `7 / 2 = 3`), máximo 15 dígitos al escribir, y la división entre cero muestra `Error` hasta pulsar `C`.

---

## 4. Conceptos previos

Para entender el código conviene conocer esto.

**Convención de llamadas System V AMD64** (cómo se llaman funciones de C desde ensamblador):

| Argumento | Registro |
|---|---|
| 1.º a 6.º (enteros / punteros) | `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9` |
| 7.º en adelante | En la pila: el 7.º en `[rsp]`, el 8.º en `[rsp+8]`, etc., justo en el momento del `call` |
| Valor de retorno | `rax` |
| Registros que la función **conserva** (callee-saved) | `rbx`, `rbp`, `r12`-`r15` |
| Registros que la función **puede destruir** | `rax`, `rcx`, `rdx`, `rsi`, `rdi`, `r8`-`r11` |

**Alineación de pila:** en el instante del `call`, `rsp` debe ser múltiplo de 16. Por eso los prólogos tienen esa cantidad concreta de `push` y `sub rsp`.

**Nombres de registros:** `rax` es de 64 bits, `eax` los 32 bajos, `ax` los 16 bajos, `al` los 8 bajos. Escribir en `eax` pone a cero la mitad alta de `rax`. En `r8`-`r15` los sufijos son `d` (32 bits), `w` (16) y `b` (8): `r8d`, `r13b`.

**Estructura `XEvent`:** es una unión de 192 bytes. El tipo de evento está en el desplazamiento 0. Los campos usados aquí:

| Evento | Campo | Desplazamiento |
|---|---|---|
| Cualquiera | `type` | 0 |
| `Expose` | `count` (eventos de expose pendientes) | 56 |
| `ButtonPress` | `x` / `y` del clic | 64 / 68 |
| `ButtonPress` | `button` (1 = izquierdo) | 84 |
| `ClientMessage` | `data.l[0]` | 56 |

**Distribución de la ventana (248 x 294 px):**

```
x=8                     x=240
 +---------------------+ y=8
 |      PANTALLA       |      232 x 50
 +---------------------+ y=58
                              (hueco)
 [7] [8] [9] [/]        y=70    cada botón 52 x 48
 [4] [5] [6] [*]        y=126   paso horizontal 60, vertical 56
 [1] [2] [3] [-]        y=182
 [C] [0] [=] [+]        y=238
```

El botón de fila `f` y columna `c` está en `x = 8 + c*60`, `y = 70 + f*56`.

---

## 5. Explicación línea por línea

### 5.1 Cabecera

- `default rel` — por defecto, las direcciones de memoria como `[display]` se codifican relativas a `rip`. Es lo que se necesita en código de 64 bits moderno.
- `global main` — hace visible el símbolo `main` para el enlazador, que lo llama desde el código de arranque.
- `extern XOpenDisplay, ...` — declara funciones que no están en este archivo; el enlazador las resolverá con libX11 (`-lX11`). Se agrupan en varias líneas solo por legibilidad.

### 5.2 Constantes (`equ`)

`equ` define una constante de ensamblado; no ocupa memoria.

- `KeyPress equ 2` — tipo de evento "tecla pulsada".
- `ButtonPress equ 4` — tipo de evento "botón del ratón pulsado".
- `Expose equ 12` — la ventana (o parte) debe redibujarse.
- `ClientMessage equ 33` — mensaje del gestor de ventanas (se usa para el botón de cerrar).
- `KeyPressMask equ 1` — máscara para recibir eventos de teclado (bit 0).
- `ButtonPressMask equ 4` — máscara para eventos de clic (bit 2).
- `ExposureMask equ 1 << 15` — máscara para eventos de redibujado (bit 15).

### 5.3 Sección `.data` (datos con valor inicial)

- `titulo: db "Calculadora", 0` — texto de la barra de título; el `0` final lo termina como cadena de C.
- `fuente: db "10x20", 0` — nombre de la fuente X que se intenta cargar (10 px de ancho, 20 de alto).
- `wmname: db "WM_DELETE_WINDOW", 0` — nombre del protocolo para detectar el cierre desde la barra de título.
- `msg_err: db "Error"` — texto de error. No lleva `0` porque `XDrawString` recibe la longitud (5) explícita.
- `botones: db "789/456*123-C0=+"` — los 16 botones por filas. La posición en la cadena (`fila*4 + columna`) identifica cada botón.
- `cw: dd 6` — ancho de un carácter en píxeles (6 = fuente por defecto). `dd` reserva 4 bytes.
- `dy: dd 5` — desplazamiento vertical para centrar el texto en su botón (se cambia a 10 y 6 si carga `10x20`).

### 5.4 Sección `.bss` (datos sin inicializar, se llenan de ceros)

- `display: resq 1` — puntero a la conexión con el servidor X (`resq 1` = 1 *quad word*, 8 bytes).
- `window: resq 1` — identificador de la ventana.
- `gc: resq 1` — contexto gráfico (color, fuente actuales).
- `wmdel: resq 1` — identificador del átomo `WM_DELETE_WINDOW`.
- `acc: resq 1` — acumulador: el primer operando de la operación pendiente.
- `cur: resq 1` — el número que se muestra en pantalla y que se está escribiendo.
- `op: resb 1` — operador pendiente (`+`, `-`, `*`, `/`) o `0` si no hay (`resb` = 1 byte).
- `nuevo: resb 1` — `1` significa que el próximo dígito empieza un número nuevo.
- `err: resb 1` — `1` si hubo división entre cero.
- `chbuf: resb 1` — buffer de 1 carácter para dibujar la etiqueta de un botón.
- `keybuf: resb 8` — buffer donde `XLookupString` deja el texto de la tecla.
- `numbuf: resb 32` — buffer donde se convierte un número a texto.
- `event: resb 192` — espacio para un `XEvent` (192 bytes).

### 5.5 `main`: prólogo

- `section .text` — a partir de aquí va el código ejecutable.
- `push rbp` / `mov rbp, rsp` — crea el marco de pila estándar.
- `push rbx`, `push r12`, `push r13`, `push r14`, `push r15` — guarda los registros que `main` va a usar y que debe devolver intactos.
- `sub rsp, 40` — reserva 40 bytes: deja la pila alineada a 16 y da sitio para los argumentos 7.º-9.º de las llamadas.

Registros usados durante todo `main`: `rbx` = display, `r12` = window, `r13` = gc.

### 5.6 `main`: crear la ventana

- `xor edi, edi` — pone `edi` a 0: primer argumento `NULL` (usar la variable de entorno `DISPLAY`).
- `call XOpenDisplay wrt ..plt` — abre la conexión con el servidor X. `wrt ..plt` llama a través de la tabla de enlace dinámico. Devuelve el puntero en `rax`.
- `test rax, rax` / `jz .error` — si es 0, no hay servidor X: salta a `.error`.
- `mov [display], rax` / `mov rbx, rax` — guarda el display en memoria (lo usan las funciones auxiliares) y en `rbx`.
- `mov rdi, rbx` / `call XDefaultRootWindow` — obtiene la ventana raíz (el escritorio), que será la ventana padre.
- `mov rsi, rax` — 2.º argumento de `XCreateSimpleWindow`: el padre.
- `mov qword [rsp], 0` — 7.º argumento: ancho del borde (0).
- `mov qword [rsp+8], 0` — 8.º argumento: color del borde.
- `mov qword [rsp+16], 0x202020` — 9.º argumento: color de fondo, gris oscuro (`0xRRGGBB`).
- `mov rdi, rbx` — 1.º argumento: display.
- `mov edx, 100` / `mov ecx, 100` — 3.º y 4.º: posición x e y inicial.
- `mov r8d, 248` / `mov r9d, 294` — 5.º y 6.º: ancho y alto.
- `call XCreateSimpleWindow` — crea la ventana (todavía invisible); devuelve su identificador en `rax`.
- `mov [window], rax` / `mov r12, rax` — lo guarda.

### 5.7 `main`: título, contexto gráfico y fuente

- `mov rdi, rbx` / `mov rsi, r12` / `lea rdx, [titulo]` / `call XStoreName` — `XStoreName(display, window, "Calculadora")` pone el título. `lea` carga la *dirección* de `titulo`.
- `xor edx, edx` / `xor ecx, ecx` / `call XCreateGC` — `XCreateGC(display, window, 0, NULL)` crea un contexto gráfico con valores por defecto.
- `mov [gc], rax` / `mov r13, rax` — lo guarda.
- `lea rsi, [fuente]` / `call XLoadQueryFont` — intenta cargar la fuente `10x20`. Devuelve un puntero a `XFontStruct` o `NULL` si no existe.
- `test rax, rax` / `jz .nofuente` — si no se pudo cargar, se queda con la fuente por defecto.
- `mov rdx, [rax+8]` — lee el campo `fid` (identificador de fuente), que está 8 bytes dentro de `XFontStruct`.
- `mov rdi, rbx` / `mov rsi, r13` / `call XSetFont` — `XSetFont(display, gc, fid)` aplica la fuente al GC.
- `mov dword [cw], 10` / `mov dword [dy], 6` — actualiza el ancho de carácter y el ajuste vertical para la fuente grande.
- `.nofuente:` — etiqueta de destino del salto anterior.

### 5.8 `main`: botón de cerrar, eventos y mostrar

- `lea rsi, [wmname]` / `xor edx, edx` / `call XInternAtom` — `XInternAtom(display, "WM_DELETE_WINDOW", False)` obtiene el identificador (átomo) de ese protocolo.
- `mov [wmdel], rax` — lo guarda para compararlo después.
- `lea rdx, [wmdel]` / `mov ecx, 1` / `call XSetWMProtocols` — `XSetWMProtocols(display, window, &atomo, 1)` avisa al gestor de ventanas de que, al pulsar la X, debe enviar un `ClientMessage` en vez de matar la conexión.
- `mov edx, KeyPressMask | ButtonPressMask | ExposureMask` / `call XSelectInput` — elige qué eventos quiere recibir esta ventana. El `|` (OR) combina las máscaras.
- `call XMapWindow` — hace visible la ventana.

### 5.9 `main`: bucle de eventos

- `.loop:` — inicio del bucle principal.
- `lea rsi, [event]` / `call XNextEvent` — espera (bloquea) hasta que llegue un evento y lo copia en `event`.
- `mov eax, [event]` — lee el tipo de evento (primeros 4 bytes).
- Los `cmp eax, X` / `je ...` — despachan según el tipo: `Expose`, `ButtonPress`, `KeyPress`, `ClientMessage`. Cualquier otro evento: `jmp .loop`.

**`.expose`**
- `cmp dword [event+56], 0` / `jne .loop` — `count` indica cuántos `Expose` quedan por llegar; solo se redibuja con el último (`count == 0`).
- `call dibujar` / `jmp .loop` — redibuja y vuelve a esperar.

**`.cliente`** (cerrar con la X)
- `mov rax, [event+56]` — `data.l[0]` del mensaje.
- `cmp rax, [wmdel]` / `je .salir` — si es el átomo de cierre, termina. Si no, vuelve al bucle.

**`.click`** (ratón)
- `cmp dword [event+84], 1` / `jne .loop` — ignora todo salvo el botón izquierdo.
- `mov eax, [event+64]` — coordenada x del clic.
- `sub eax, 8` / `jl .loop` — resta el margen izquierdo; si es negativo, el clic cayó fuera de los botones.
- `xor edx, edx` / `mov ecx, 60` / `div ecx` — divide `edx:eax` entre 60: `eax` = columna, `edx` = resto dentro de esa celda.
- `cmp eax, 4` / `jge .loop` — columna 4 o más: fuera.
- `cmp edx, 52` / `jge .loop` — el resto es de 52 o más: cayó en el hueco de 8 px entre botones.
- `mov r14d, eax` — guarda la columna.
- `mov eax, [event+68]` / `sub eax, 70` / `jl .loop` — coordenada y menos el inicio de los botones (zona de la pantalla = ignorar).
- `xor edx, edx` / `mov ecx, 56` / `div ecx` — fila y resto, igual que antes con paso vertical 56.
- `cmp eax, 4` / `jge .loop` y `cmp edx, 48` / `jge .loop` — fuera de las filas o en el hueco vertical.
- `shl eax, 2` — multiplica la fila por 4 (desplazar 2 bits a la izquierda).
- `add eax, r14d` — índice = `fila*4 + columna`.
- `lea rcx, [botones]` / `movzx edi, byte [rcx+rax]` — lee el carácter de ese botón en la cadena `botones` y lo pone como argumento de `pulsar`.
- `call pulsar` / `call dibujar` / `jmp .loop` — procesa la pulsación, repinta y sigue.

**`.tecla`** (teclado)
- `lea rdi, [event]` / `lea rsi, [keybuf]` / `mov edx, 8` / `xor ecx, ecx` / `xor r8d, r8d` / `call XLookupString` — traduce el código de tecla a texto: `XLookupString(&evento, buffer, 8, NULL, NULL)`. Devuelve en `eax` cuántos caracteres produjo.
- `test eax, eax` / `jz .loop` — 0 caracteres (Shift, Ctrl, flechas...): se ignora.
- `movzx edi, byte [keybuf]` — toma el primer carácter.
- `cmp edi, 13` / `je .enter` — 13 es Enter.
- `cmp edi, 'c'` / `je .minc` — `c` minúscula.
- `cmp edi, 'x'` / `je .porx` — `x` como multiplicar.
- `cmp edi, 'q'` / `je .salir` y `cmp edi, 27` / `je .salir` — `q` y Escape (27) salen.
- `jmp .enviar` — cualquier otro carácter se envía tal cual.
- `.enter: mov edi, '='` — Enter se convierte en `=`.
- `.minc: mov edi, 'C'` — `c` se convierte en `C`.
- `.porx: mov edi, '*'` — `x` se convierte en `*`.
- `.enviar: call pulsar` / `call dibujar` / `jmp .loop` — igual que con el ratón. Así teclado y ratón comparten toda la lógica.

### 5.10 `main`: salida y epílogo

- `.salir:` — `mov rdi, rbx` / `mov rsi, r13` / `call XFreeGC` libera el GC; `mov rdi, rbx` / `call XCloseDisplay` cierra la conexión con X.
- `xor eax, eax` / `jmp .fin` — código de salida 0 (éxito).
- `.error: mov eax, 1` — código de salida 1 (no se pudo abrir el display).
- `.fin:` — `add rsp, 40` libera lo reservado y `pop r15` ... `pop rbp` restaura los registros en orden inverso al de los `push`. `ret` termina `main`.

### 5.11 `pulsar`: la lógica de la calculadora

Recibe el carácter en `dil` (parte baja de `rdi`). No llama a funciones externas, así que no necesita alinear la pila.

- `movzx eax, dil` — copia el carácter a `eax` ampliándolo con ceros.
- `cmp al, 'C'` / `jne .noC` — si es `C`, limpia el estado: `acc`, `cur`, `op`, `nuevo` y `err` se ponen a 0, y `ret`.
- `.noC: cmp byte [err], 0` / `jne .ret` — en estado de error solo se acepta `C`.
- Bloque Backspace: `cmp al, 8` / `jne .nobs`; si `nuevo` es distinto de 0 no se borra (se muestra un resultado); si no, `mov rax, [cur]` / `cqo` / `mov rcx, 10` / `idiv rcx` divide `cur` entre 10 (se pierde el último dígito) y `mov [cur], rax`. `cqo` extiende el signo de `rax` en `rdx`, necesario antes de `idiv`.
- `.nobs: cmp al, '0'` / `jb .oper` y `cmp al, '9'` / `ja .oper` — si no está entre `'0'` y `'9'`, no es dígito: salta a operadores.

**Dígito**
- `cmp byte [nuevo], 0` / `je .acum` — si `nuevo` es 0, se sigue escribiendo el mismo número.
- `mov qword [cur], 0` / `mov byte [nuevo], 0` — si `nuevo` era 1, se empieza un número desde cero.
- `.acum: mov rcx, [cur]` — número actual.
- `mov rdx, 100000000000000` / `cmp rcx, rdx` / `jge .ret` — si ya tiene 15 dígitos, ignora el dígito (evita desbordar).
- `sub eax, '0'` — convierte el carácter ASCII en su valor (`'7'` pasa a 7).
- `imul rcx, rcx, 10` / `add rcx, rax` / `mov [cur], rcx` — `cur = cur * 10 + dígito`.
- `ret`.

**Operador o `=`** (`.oper:`)
- Los `cmp al, '+'` / `je .ok` (y los de `-`, `*`, `/`) y `cmp al, '='` / `jne .ret` — si no es ninguno de esos, se ignora la tecla.
- `.ok: mov r8d, eax` — guarda la tecla pulsada en `r8b`.
- `cmp byte [op], 0` / `je .sinop` — sin operador pendiente, no hay nada que calcular.
- `cmp byte [nuevo], 0` / `jne .sinop` — si `nuevo` es 1 (se pulsó un operador y todavía no un número), solo se cambia el operador; no se calcula.
- `mov rax, [acc]` / `mov rcx, [cur]` / `movzx edx, byte [op]` — carga los dos operandos y el operador pendiente.
- `cmp dl, '+'` / `jne .n1` / `add rax, rcx` / `jmp .res` — suma. Igual con `.n1` (resta, `sub`), `.n2` (multiplicación, `imul`).
- `.n3:` (división) — `test rcx, rcx` / `jz .diverr` evita dividir entre cero; `cqo` / `idiv rcx` divide `rdx:rax` entre `rcx` y deja el cociente en `rax`.
- `.res: mov [cur], rax` — el resultado pasa a ser el número en pantalla.
- `.sinop: mov rax, [cur]` / `mov [acc], rax` — el valor mostrado pasa a ser el acumulador para la siguiente operación.
- `mov byte [nuevo], 1` — el próximo dígito empezará un número nuevo.
- `cmp r8b, '='` / `jne .setop` — si fue `=`, `mov byte [op], 0` y `ret` (no queda operación pendiente).
- `.setop: mov [op], r8b` / `ret` — si fue otro operador, queda pendiente.
- `.diverr: mov byte [err], 1` — activa el estado de error y cae a `.ret`.
- `.ret: ret`.

Ejemplo: `5 + 3 =`. Se pulsa `5` (`cur=5`), `+` (`acc=5`, `op='+'`, `nuevo=1`), `3` (`cur=3`, `nuevo=0`), `=` (calcula `5+3`, `cur=8`, `acc=8`, `op=0`).

### 5.12 `num2str`: número a texto

Entrada: `rax` = valor con signo. Salida: `rsi` = inicio del texto, `rdx` = longitud. Escribe los dígitos de derecha a izquierda dentro de `numbuf`.

- `lea rsi, [numbuf+30]` — empieza por el penúltimo byte del buffer (el último dígito irá ahí).
- `xor r8d, r8d` — `r8d` = bandera "es negativo" (0).
- `test rax, rax` / `jns .pos` — si no es negativo, salta.
- `neg rax` / `mov r8d, 1` — si es negativo, se trabaja con su valor absoluto y se anota.
- `.pos: mov r9d, 10` — divisor.
- `.dig: xor edx, edx` / `div r9` — divide `rdx:rax` entre 10: cociente en `rax`, resto en `rdx` (0 a 9).
- `add dl, '0'` — convierte el resto a carácter ASCII.
- `mov [rsi], dl` / `dec rsi` — lo escribe y retrocede una posición.
- `test rax, rax` / `jnz .dig` — repite mientras queden dígitos (así `0` produce un `'0'`).
- `test r8d, r8d` / `jz .fin` — si era negativo, `mov byte [rsi], '-'` / `dec rsi` añade el signo.
- `.fin: inc rsi` — `rsi` quedó una posición antes del primer carácter; se corrige.
- `lea rdx, [numbuf+31]` / `sub rdx, rsi` — longitud = fin del texto menos inicio.

### 5.13 Funciones auxiliares de dibujo

**`setfg`** — `rdi` = color. Hace `XSetForeground(display, gc, color)`:
- `push rbp` / `mov rbp, rsp` / `pop rbp` — marco de pila; además deja la pila alineada para el `call`.
- `mov rdx, rdi` — el color pasa a 3.º argumento.
- `mov rdi, [display]` / `mov rsi, [gc]` — 1.º y 2.º argumento (se hace después de copiar el color porque `rdi` se sobrescribe).

**`frect`** — rectángulo relleno. Entrada: `edi`=x, `esi`=y, `edx`=ancho, `ecx`=alto, `r8`=color.
- Guarda `x, y, w, h` en `ebx`, `r12d`, `r13d`, `r14d` (registros callee-saved, así sobreviven a la llamada a `XSetForeground`, que destruye `rdi`, `rsi`, `rdx`, `rcx`, `r8`).
- `sub rsp, 16` — alinea la pila y deja el hueco `[rsp]` del 7.º argumento.
- Llama a `XSetForeground(display, gc, color)` con `mov rdx, r8`.
- Prepara `XFillRectangle(display, window, gc, x, y, ancho, alto)`: `rdi`, `rsi`, `rdx` = display, window, gc; `ecx` = x; `r8d` = y; `r9d` = ancho; `[rsp]` = alto (7.º argumento, en la pila).
- Restaura registros y `ret`.

**`texto`** — dibuja una cadena. Entrada: `edi`=x, `esi`=y (línea base), `rdx`=puntero, `rcx`=longitud.
- `sub rsp, 16` / `mov [rsp], rcx` — la longitud es el 7.º argumento de `XDrawString`, va en la pila.
- `mov r9, rdx` — el puntero al texto es el 6.º argumento.
- `mov ecx, edi` / `mov r8d, esi` — x e y pasan al 4.º y 5.º argumento. El orden es importante: hay que copiar antes de sobrescribir `rdi`, `rsi`, `rdx`, `rcx`.
- `mov rdi, [display]` / `mov rsi, [window]` / `mov rdx, [gc]` — primeros tres argumentos.
- `call XDrawString` — `XDrawString(display, window, gc, x, y, texto, longitud)`.
- `leave` / `ret` — `leave` equivale a `mov rsp, rbp` + `pop rbp`.

### 5.14 `dibujar`: repinta toda la ventana

- Prólogo: `push rbp`, `mov rbp, rsp`, `push rbx`, `push r12`, `push r13`, `push r14` (los cuatro registros que usa y debe conservar).

**Pantalla**
- `mov edi, 8` / `mov esi, 8` / `mov edx, 232` / `mov ecx, 50` / `mov r8d, 0x101010` / `call frect` — rectángulo casi negro (esto también borra el número anterior).
- `mov edi, 0xffffff` / `call setfg` — color blanco para el texto.
- `cmp byte [err], 0` / `je .num` — si hay error: `lea rsi, [msg_err]` / `mov edx, 5` / `jmp .pintar`.
- `.num: mov rax, [cur]` / `call num2str` — si no, convierte `cur` a texto (`rsi`, `rdx`).
- `.pintar:` — `mov ecx, edx` (longitud), `mov r12, rsi` y `mov r13, rdx` (guardan puntero y longitud).
- `imul ecx, dword [cw]` — ancho en píxeles del texto = longitud * ancho de carácter.
- `mov edi, 222` / `sub edi, ecx` — x = 222 - ancho: alinea el número a la derecha de la pantalla.
- `cmp edi, 12` / `jge .xok` / `mov edi, 12` — si es demasiado largo, no sale por la izquierda.
- `mov esi, 33` / `add esi, dword [dy]` — y de la línea base: centro vertical de la pantalla (33) más ajuste.
- `mov rdx, r12` / `mov rcx, r13` / `call texto` — dibuja el número.

**Botones** (`r14d` = índice 0 a 15)
- `xor r14d, r14d` / `.btn: cmp r14d, 16` / `jge .fin` — recorre los 16 botones.
- `mov eax, r14d` / `shr eax, 2` — fila = índice / 4 (desplazar 2 bits a la derecha).
- `imul eax, 56` / `add eax, 70` / `mov r12d, eax` — `y = 70 + fila*56`, queda en `r12d`.
- `mov eax, r14d` / `and eax, 3` — columna = índice % 4.
- `imul eax, 60` / `add eax, 8` / `mov ebx, eax` — `x = 8 + columna*60`, queda en `ebx`.
- `lea rax, [botones]` / `movzx r13d, byte [rax+r14]` — carácter del botón en `r13`.
- `mov r8d, 0x3c3c3c` — color por defecto (gris), para dígitos.
- `cmp r13b, 'C'` / `jne .c1` / `mov r8d, 0xb03030` / `jmp .cdone` — la `C` va en rojo.
- `.c1: cmp r13b, '0'` / `jb .oper` y `cmp r13b, '9'` / `jbe .cdone` — si es dígito, deja el gris. Si no, cae en `.oper`.
- `.oper: mov r8d, 0xd9822b` — operadores y `=` en naranja.
- `.cdone: mov edi, ebx` / `mov esi, r12d` / `mov edx, 52` / `mov ecx, 48` / `call frect` — dibuja el rectángulo del botón (52 x 48) con el color elegido.
- `mov edi, 0xffffff` / `call setfg` — blanco para la etiqueta.
- `mov eax, 52` / `sub eax, dword [cw]` / `shr eax, 1` / `add eax, ebx` / `mov edi, eax` — x centrada: `x_botón + (52 - ancho_carácter) / 2`.
- `mov esi, r12d` / `add esi, 24` / `add esi, dword [dy]` — y: mitad del botón (24) más ajuste.
- `mov [chbuf], r13b` / `lea rdx, [chbuf]` / `mov ecx, 1` / `call texto` — dibuja el carácter como cadena de longitud 1.
- `inc r14d` / `jmp .btn` — siguiente botón.
- `.fin:` — restaura `r14`, `r13`, `r12`, `rbx`, `rbp` y `ret`.

### 5.15 Última línea

- `section .note.GNU-stack noalloc noexec nowrite progbits` — sección vacía que indica al enlazador que el programa **no** necesita pila ejecutable. Sin ella, binutils recientes muestran la advertencia "missing .note.GNU-stack section implies executable stack".

---

## 6. Problemas frecuentes

| Síntoma | Causa y solución |
|---|---|
| `cannot find -lX11` | Falta el paquete de desarrollo de libX11 (ver sección 1). |
| `undefined reference to 'XOpenDisplay'` | Olvidaste `-lX11` al enlazar. |
| La ventana no se abre y el programa sale con código 1 | `XOpenDisplay` falló: no hay servidor X o `DISPLAY` no está definida. En Wayland necesitas XWayland. |
| Advertencia `missing .note.GNU-stack` | Falta la última línea del `.asm`; ya está incluida. |
| Los botones salen con letra pequeña | La fuente `10x20` no está instalada; se usa la de por defecto, y funciona igual. |
| Colores raros | Los colores asumen una pantalla de 24 bits (TrueColor), que es lo habitual hoy. |

