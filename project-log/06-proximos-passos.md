# 06 — Proximos passos (em ordem)

1. **Terminar o `libvulkan.a`.** Rodar `tools/win/build_nvk.ps1 -Jobs 24` e atacar o que restar
   (grupo bindgen, item 17 de `05-nvk.md`). Verificar com:
   `Get-ChildItem out/mesa -Recurse -Filter libvulkan.a`.
2. **Instalar o NVK:** o proprio script instala em `mesa-switch-install/` e imprime o `NVK_SDK` a usar.
3. **Compilar o NRO:** `tools/win/build_switch.ps1` -> `out/nx/fc3.nro`.
4. **Empacotar o SD:** `tools/win/package_switch.ps1` -> `out/nx/sdcard/switch/fc3-nx/`.
5. **Copiar para o cartao:** `fc3-nx/` para `sdmc:/switch/` (+ `game_root.nxpack`/`.nxidx` via
   `-IncludeGame`, ou pasta `game_root` solta com `-LooseGame`).
6. **Title Update (paralelo, so o usuario pode fazer):** emprestar
   `Far Cry 3 (World) (v5) (6F6EAD36) (Title Update).zip` em
   `archive.org/details/microsoft_xbox360_title-updates` (conta + emprestimo, 7,48 MB), extrair o
   `.xexp` com `tools/stfs_extract.py`, converter para o par `patch.dat`/`patch.fat` e por em
   `UPDATE:\` (ou `assets/update/` no PC). Sem isso o jogo para na tela de disco sujo.
7. **Depois do NRO:** loop de boot no console (Etapa 1 ate a title screen), e so entao Etapa 2
   (renderer nativo — `app/src/me/` precisa ser readaptado do SA2 para o XDK do FC3).

## Acoes manuais pendentes do usuario

- [ ] Conseguir o Title Update (item 6 acima) — **unico desbloqueio que so o usuario pode fazer**
- [ ] Copiar o pacote SD para o cartao quando o `.nro` existir
- [ ] Testar no Switch (hbmenu com title takeover: segurar R num jogo)