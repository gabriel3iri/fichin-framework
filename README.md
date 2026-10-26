# fichin-framework

**jornada**: framework para Godot 4.7 (GDScript tipado, GL Compatibility, 640×360) de juegos 2D top-down armados
alrededor de un día: reloj, gente con horarios, conversaciones con condiciones, diario, trabajo y lo que pasa cuando
la jornada termina (vuelve el mismo día o pasa al siguiente).

- `addons/jornada/`: el framework. Su documentación está en [`addons/jornada/README.md`](addons/jornada/README.md).
- `examples/primer_dia/`: juego de ejemplo chico (dos zonas, tres vecinos, tres días). Enlaza el addon con un
  symlink y corre sus pruebas con `./run_tests.sh`.

## Usarlo en un juego

El repo se agrega como submódulo y el addon se enlaza:

```bash
git submodule add https://github.com/gabriel3iri/fichin-framework.git framework
ln -s ../framework/addons/jornada addons/jornada
```

Para actualizar: `git -C framework pull` y commitear el submódulo en el juego.

## De dónde sale

El framework nació dentro de Rabenholz 17:47 y se sigue desarrollando ahí. Este repo es la copia publicada:
`tools/sync_from.sh <ruta-al-juego> [rama]` trae `addons/jornada/` y `examples/` de esa rama del juego
(por defecto `origin/main`) para commitearlos acá.
