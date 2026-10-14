# Etapa 28.68 — Operações sem efeito nos limites do texto

Dois testes de regressão verificam que navegação nos limites e exclusões impossíveis não modificam o armazenamento nem o estado do editor. Navegação com seleção ativa preserva a âncora; exclusão sem seleção efetiva e com âncora colapsada preserva a representação anterior. Nenhuma alteração de runtime ou API pública.

Validação Zig 0.17.0 ainda pendente, pois o compilador não está disponível no ambiente.
