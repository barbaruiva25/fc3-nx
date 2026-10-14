# Guia geral de ports de jogos para Nintendo Switch — referencia parcial (v1.36, 11/10/2026)

Recebido do usuario em 2026-10-13 (texto parcial: secoes 1-11, cortado no meio da 11).
Arquivo completo nao recebido; aplicar apenas o que e compativel com o fc3-nx.
Guia independente de jogo; exemplos `meu_jogo`/`game_target` sao ilustrativos.

## O que foi extraido para o fc3-nx (13/10)

- Contrato de entrega (ZIP `switch/<jogo>/<jogo>.nro` + arquivos, sem dados do jogo): `out/packages/`.
- Tabela de estado honesta (compilou != inicializa != menu != gameplay): usada nas notas de release.
- Regra 6.4 (host acessivel != guest mapeado; validar intervalo antes de copiar; nao remover
  protecao): base teorica dos crashes atuais (`0x04020000`, `0x0502FF08`).
- Regra 6.2 (branch indireto: investigar tabelas/callbacks, nao retornar zero): base do `overrides.toml`.
- Manutencao por rodada (19.1): `project-log/` atualizado a cada push.

## Texto recebido (ipsis litteris, parcial)

Guia geral de ports de jogos para Nintendo Switch
Versão: 1.36 — atualização em 11 de outubro de 2026.

[Texto integral recebido do usuario — secoes 1 a 11 parcial. O conteudo completo esta
abaixo como referencia; as secoes 12+ nao foram recebidas.]

---

(Seção 1 — Como usar este guia em um novo projeto)

Primeiro identifique o caminho de port adequado e o estado real dos materiais disponíveis. Depois produza um executável mínimo verificável, avance até gameplay correto e só então use medições para escolher otimizações. A ordem evita gastar dias otimizando uma implementação que ainda executa o código errado.

Distinga sempre estas situações:

Estado | O que demonstra | O que ainda não demonstra
Compilação terminou | O compilador e o linker aceitaram os arquivos | Que o executável inicializa no console
NRO abre | Inicialização básica funciona | Que o jogo correto foi carregado
Menu aparece | Parte da CPU, vídeo e dados funciona | Gameplay, streaming, saves ou estabilidade
Gameplay funciona | Um caminho representativo já é executável | Todas as fases, missões e transições
LTO verificado | Os objetos pretendidos participaram da otimização de link | Ganho de FPS no aparelho
PGO GENERATE | Existe um executável que produz contadores | Que os perfis foram gravados ou aplicados
Perfil exportado | Arquivos de treino foram produzidos | Compatibilidade e consistência para USE
PGO USE | A compilação consumiu perfis validados | Ganho de desempenho ou ausência de regressões
Teste controlado aprovado | Uma melhoria foi medida sob condições registradas | Resultado idêntico em todo o jogo

(Seções 2–11 conforme texto enviado: escolha do caminho — para FC3 vale 2.2 recompilação
estática; hardware/metas §3 — Tegra X1, modo aplicativo via title takeover, resoluções
separadas; ambiente §4 — devkitA64/libnx, manifesto de ferramentas, nunca -march=native
no Switch; inventário §5; §6.1 endianness, §6.2 branches indiretos, §6.3 hooks, §6.4 memória
guest e exceções; §7 serviços Horizon; §8 renderer nativo por passagens; §9 shaders/pipelines;
§10 orçamento de memória; §11 CPU/threads/áudio.)

NOTA: o corpo integral das seções 2–11 foi recebido no chat em 2026-10-13 e serve como
leitura de apoio; este arquivo registra apenas o essencial aplicado. Leitura completa
recomendada antes da Etapa 3 (Switch): toolchain Cortex-A57, NVK/mesa-switch fixado por
commit, pacotes ZIP por build-id, telemetria por sessão (evidence/hardware/<sessao>).
