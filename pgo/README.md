# pgo/ - perfil de otimizacao guiado por perfil

Vazio. O perfil do Sonic Adventure 2 que estava aqui foi removido: os arquivos `.gcda` nomeiam o caminho de build
daquele projeto (`.../sonic_adventure_2/sa2-nx/...`) e as funcoes que eles mediram nao existem neste port. O guia
(secao 9.2) e explicito: o perfil so vale para o codigo com que foi coletado, e uma funcao alterada perde a parte
dele.

Para gerar um perfil deste port:

1. `powershell -NoProfile -ExecutionPolicy Bypass -File tools\win\build_switch.ps1 -Pgo generate` — constroi um NRO
   instrumentado. Ele escreve `fc3_pgo_<N>.stream` no console a cada 2 minutos, e tambem no botao HOME e na saida.
2. Jogue no console. Copie a pasta `pgo/` do console para o PC.
3. No PC **que construiu** o NRO instrumentado (o stream nomeia a pasta de perfil daquele build):
   `powershell -NoProfile -ExecutionPolicy Bypass -File tools\win\pgo_merge.ps1 <pasta>`
   e depois `python tools\pgo_summary.py`.
4. `powershell -NoProfile -ExecutionPolicy Bypass -File tools\win\build_switch.ps1 -Pgo use`.

Nao mude codigo entre os passos 1 e 4. Uma sessao de jogo vale alguns por cento: no SA2, uns 15 %, o suficiente
para o jogo de um jogador nao cair abaixo de 60 FPS.