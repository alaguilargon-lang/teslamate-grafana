# Prueba de TeslaMate y Grafana en Northflank

La imagen usa la versión de TeslaMate que indiques en GitHub Actions. Reúne el registrador de TeslaMate y Grafana en un solo despliegue. Conserva el histórico en el PostgreSQL del proyecto y crea una base independiente, `grafana`, para las preferencias y las cuentas de Grafana.

## 1. Compilar y probar en GitHub

1. Crea un repositorio nuevo llamado `teslamate-grafana` e inicialízalo con un README. Puedes crearlo como público. Los archivos del paquete no contienen contraseñas reales. Las credenciales se introducirán en Northflank.
2. Sube el contenido de esta carpeta a la raíz del repositorio. Incluye la carpeta oculta `.github`. En Finder puedes mostrarla con `⌘ + Mayús + .`. Comprueba que `.github/workflows/build.yml` aparece en la rama principal. Si falta, usa **Add file → Create new file**, escribe esa ruta y pega el contenido del archivo del paquete.
3. Abre **Actions → Compilar y probar TeslaMate con Grafana → Run workflow**. Introduce la versión exacta que aparece al pie de tu TeslaMate, quitando la `v` inicial. Conserva el número completo, por ejemplo `4.4.0`.
4. Espera a que el flujo termine correctamente. Usa la ruta de imagen que aparece en **Summary**. La prueba crea un PostgreSQL desechable, verifica que TeslaMate y Grafana arrancan con 512 MiB y 0,2 vCPU compartidos, y comprueba una consulta autenticada de Grafana. La prueba no utiliza datos de tu coche.
5. En GitHub, abre el paquete recién creado y ve a **Package settings → Change visibility → Public** si figura como privado. El contenedor es público, las variables que le añadas en Northflank se configuran aparte.

## 2. Preparar PostgreSQL

En **Northflank → Default → postgres-teslamate → Shell**, ejecuta `psql -U postgres -d teslamate`. Después ejecuta lo siguiente.

```sql
CREATE USER grafana_server;
CREATE DATABASE grafana OWNER grafana_server;
REVOKE CONNECT ON DATABASE grafana FROM PUBLIC;
\password grafana_server
```

Escribe dos veces una contraseña nueva para `grafana_server` y guárdala. Sal con `\q`. La cuenta `grafana_reader` que ya usa tu Mac sirve para leer el historial. `grafana_server` guarda los ajustes de Grafana en su propia base.

## 3. Configurar y desplegar

Abre el servicio `teslamateservice`. Anota la imagen actual para poder recuperarla. Conserva las variables de entorno actuales de TeslaMate y añade estas cuatro.

| Variable | Valor |
| --- | --- |
| `GRAFANA_READER_PASSWORD` | La contraseña que ya tienes de `grafana_reader`. |
| `GRAFANA_DB_PASSWORD` | La nueva contraseña de `grafana_server`. |
| `GRAFANA_ADMIN_PASSWORD` | Otra contraseña nueva, de al menos 16 caracteres. La usarás para entrar en Grafana como `admin`. |
| `GRAFANA_SECRET_KEY` | Otra clave nueva y estable, de al menos 32 caracteres. Grafana la usa para cifrar credenciales. |

Puedes generar cada clave aleatoria en el Mac con `openssl rand -hex 32 | pbcopy`. Eso la copia al portapapeles sin mostrarla. Guarda cada clave en tu gestor de contraseñas antes de generar la siguiente.

1. En **Overview → Edit image source → External image**, pega la ruta de `ghcr.io` de tu ejecución. Deja el comando, el entrypoint y el usuario en los valores de la imagen. Aplica **Update & rollout restart** en un momento en que el coche esté aparcado. Si tu panel ofrece **Recreate** en las opciones de despliegue, elígelo para que el registrador anterior se detenga antes de arrancar el nuevo.
2. En **Logs**, comprueba que aparece el inicio de Grafana en el puerto `3000` y que también arranca TeslaMate. Mantén `4000` de TeslaMate y `5432` de PostgreSQL privados.
3. En **Networking** del servicio `teslamateservice`, añade un puerto llamado `grafana`, **HTTP**, `3000`. Ponlo **Private** primero para comprobarlo por el túnel habitual de `teslamateservice`. Ejecuta `~/.local/bin/nf forward service --projectId default --serviceId teslamateservice --skipHostnames` y abre la dirección local que corresponda al puerto interno `3000`. Entra como `admin` con `GRAFANA_ADMIN_PASSWORD` y comprueba **Drives** y **Charges**.

## 4. Abrir desde Android

1. Cambia únicamente el puerto `grafana` a **Public** en Northflank. Copia la URL HTTPS que Northflank muestra para ese puerto.
2. Añade en **Environment** la variable `GRAFANA_ROOT_URL` con esa URL HTTPS y una `/` al final. Este ajuste usa cookies de sesión seguras. Guarda y espera a que termine el reinicio del servicio.
3. Abre la URL en Chrome de Android y verifica que en una pestaña de incógnito pide iniciar sesión. Entra y comprueba el mapa de un trayecto. Puedes crear un acceso directo desde **⋮ → Instalar y crear acceso directo → Crear acceso directo**.
4. Durante el primer trayecto registrado después del cambio, revisa **Metrics** y **Logs** de `teslamateservice`. La prueba de GitHub verifica el arranque y una consulta sencilla. La carga de tus mapas y el registro continuo se comprueban aquí. Si se acerca repetidamente al límite de memoria o deja de registrar, vuelve a la imagen anterior.

## Volver a la imagen anterior

En `teslamateservice`, cambia `grafana` de nuevo a **Private** o elimina ese puerto. En **Overview → Edit image source**, restaura la imagen anterior y despliega. La base histórica sigue en `postgres-teslamate` y puedes volver a verla con la aplicación Grafana del Mac. La base nueva `grafana` puede quedar guardada para una prueba posterior.

## Componentes

- [TeslaMate y sus paneles originales](https://github.com/teslamate-org/teslamate).
- [Grafana](https://github.com/grafana/grafana).

El `Dockerfile` usa las imágenes publicadas por ambos proyectos. El script de inicio del contenedor ejecuta cada proceso con su propio usuario de Linux.
