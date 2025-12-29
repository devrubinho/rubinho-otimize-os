# Scripts de Otimização de Sistema

## Visão Geral do Projeto

Um kit de ferramentas de otimização de sistema multiplataforma que ajuda os usuários a limpar e otimizar recursos do sistema quando o computador está lento. Este projeto fornece scripts de otimização dedicados para macOS e Linux.

**Funcionalidades:**
- **Otimização de Memória**: Limpa memória inativa, limpa caches e libera RAM
- **Otimização de CPU**: Identifica e gerencia processos intensivos em CPU
- **Gerenciamento de Disco**: Analisa uso de disco e limpa arquivos desnecessários
- **Monitoramento do Sistema**: Dashboard de desempenho em tempo real
- **Segurança em Primeiro Lugar**: Modo dry-run, preview antes da limpeza, suporte a rollback

## ⚠️ Aviso

<div style="background-color: #fff3cd; border-left: 4px solid #ffc107; padding: 12px; margin: 16px 0;">

**Use com cautela!** Estes scripts realizam operações em nível de sistema que podem afetar o desempenho e a estabilidade do seu computador. Sempre:

- Execute com `--dry-run` primeiro para visualizar as mudanças
- Certifique-se de ter backups de dados importantes
- Feche aplicativos críticos antes de executar
- Teste em sistemas não-produção primeiro

</div>

## Pré-requisitos

- **macOS**: 10.13+ (High Sierra ou superior)
- **Linux**: Ubuntu 20.04+, Fedora 36+, Debian 11+, ou Arch Linux
- **Bash**: 4.0+ (verifique com `bash --version`)
- **Acesso sudo**: Necessário para operações em nível de sistema
- **Espaço em disco**: Pelo menos 5GB livres recomendado

## Instalação

1. Clone o repositório:
```bash
git clone https://github.com/rbinoliveira/rbin-otimize-os.git
cd rbin-otimize-os
```

2. Execute o script principal (a configuração é automática):
```bash
bash run.sh
```

O script irá automaticamente:
- Detectar seu sistema operacional (macOS ou Linux)
- Executar a configuração se necessário (cria diretórios, define permissões)
- Mostrar um menu interativo com todas as opções disponíveis

Pronto! Nenhuma configuração manual necessária.

## Uso

### Início Rápido

**macOS:**
```bash
# Visualizar mudanças (recomendado primeiro)
./mac/optimize-all.sh --dry-run

# Executar otimização completa
./mac/optimize-all.sh

# Modo rápido (não interativo)
./mac/optimize-all.sh --quick
```

**Linux:**
```bash
# Visualizar mudanças (recomendado primeiro)
./linux/optimize-all.sh --dry-run

# Executar otimização completa
./linux/optimize-all.sh

# Modo agendado (para cron)
./linux/optimize-all.sh --scheduled
```

### Scripts Individuais

**Limpeza de Memória:**
```bash
# macOS
./mac/clean-memory.sh --dry-run
./mac/clean-memory.sh --aggressive

# Linux
./linux/clean-memory.sh --dry-run
./linux/clean-memory.sh --cache-level 3
```

**Otimização de CPU:**
```bash
# macOS
./mac/optimize-cpu.sh --dry-run
./mac/optimize-cpu.sh --process-threshold 50

# Linux
./linux/optimize-cpu.sh --dry-run
./linux/optimize-cpu.sh --process-threshold 30
```

**Gerenciamento de Disco:**
```bash
# Analisar uso de disco
./mac/analyze-disk.sh --dry-run
./mac/analyze-disk.sh --items=20

# Limpar espaço em disco
./mac/cleanup-disk.sh --dry-run
./mac/cleanup-disk.sh --force --min-age=30

# Linux
./linux/analyze-disk.sh --dry-run
./linux/cleanup-disk.sh --dry-run --force
```

## Descrição dos Scripts

### Scripts macOS

#### `clean-memory.sh`
- Limpa memória inativa usando `purge`
- Limpa cache de disco
- Limpa caches DNS e de fontes
- Limpa caches de usuário e sistema
- **Tempo de execução**: ~30-60 segundos
- **Memória liberada típica**: 2-8 GB

#### `optimize-cpu.sh`
- Identifica processos intensivos em CPU
- Terminação segura de processos (protege processos críticos)
- Limpeza de logs do sistema (ASL e logs unificados)
- Verificação de indexação do Spotlight
- Auditoria de daemons de inicialização
- **Tempo de execução**: ~20-40 segundos

#### `optimize-all.sh`
- Orquestra todas as tarefas de otimização
- Indicadores de progresso
- Relatórios JSON abrangentes
- Snapshots do sistema e pontos de restauração
- **Tempo de execução**: ~60-120 segundos

#### `analyze-disk.sh`
- Analisa uso de disco por categoria (caches, logs, downloads, temp, etc.)
- Mostra os N maiores arquivos e pastas
- Identifica oportunidades de limpeza
- Relatório categorizado de uso de disco
- **Tempo de execução**: ~30-90 segundos

#### `cleanup-disk.sh`
- Limpa arquivos desnecessários para liberar espaço em disco
- Preview antes da limpeza (mostra o que será deletado)
- Prompts de confirmação interativos
- Filtragem por idade (--min-age=N dias)
- Exclusão segura com suporte a rollback
- **Tempo de execução**: ~60-180 segundos

### Scripts Linux

#### `clean-memory.sh`
- Limpa cache de páginas, dentries e inodes
- Gerenciamento de swap (limpa se uso >50%)
- Limpeza de cache de gerenciadores de pacotes (apt/dnf/pacman)
- Limpeza de journal do systemd (mantém últimos 7 dias)
- Limpeza de cache de miniaturas
- **Tempo de execução**: ~20-50 segundos
- **Memória liberada típica**: 1-4 GB

#### `optimize-cpu.sh`
- Monitoramento de uso de CPU
- Gerenciamento de processos com proteção safe-kill
- Rotação e limpeza de logs do sistema
- Detecção de processos zumbi
- Auditoria de serviços systemd
- **Tempo de execução**: ~30-60 segundos

#### `optimize-all.sh`
- Fluxo de trabalho de otimização completo
- Detecção de distribuição
- Captura de snapshot do sistema
- Geração de relatório JSON
- Notificações por email (opcional)
- **Tempo de execução**: ~60-150 segundos

#### `analyze-disk.sh`
- Analisa uso de disco por categoria
- Categorias específicas da plataforma (apt/yum/pacman/snap para Linux)
- Mostra os N maiores itens (arquivos e pastas combinados)
- Identifica oportunidades de limpeza acima do threshold
- **Tempo de execução**: ~30-90 segundos

#### `cleanup-disk.sh`
- Limpa espaço em disco removendo arquivos desnecessários
- Específico para Linux: caches de gerenciadores de pacotes, volumes Docker, kernels antigos
- Mecanismo de preview antes da limpeza
- Filtragem por idade para limpeza seletiva
- Exclusão segura com tratamento adequado de permissões
- **Tempo de execução**: ~60-180 segundos

## Segurança na Limpeza de Disco

A funcionalidade de limpeza de disco inclui vários mecanismos de segurança:

- **Modo Preview**: Sempre mostra o que será limpo antes da exclusão
- **Confirmações Interativas**: Solicita confirmação antes de deletar arquivos
- **Suporte a Dry-Run**: Use `--dry-run` para visualizar sem fazer mudanças
- **Filtragem por Idade**: Use `--min-age=N` para limpar apenas arquivos mais antigos que N dias
- **Modo Force**: Use `--force` para pular confirmações (use com cautela)

**O que é limpo:**
- Caches do usuário (`~/Library/Caches` no macOS, `~/.cache` no Linux)
- Logs do sistema (arquivos de log antigos)
- Arquivos temporários (`/tmp`, `/var/tmp`)
- Lixeira/reciclagem do navegador
- Caches de gerenciadores de pacotes (apt, yum, pacman, snap no Linux)
- Cache de node modules
- Volumes Docker (se especificado)

**O que NÃO é limpo:**
- Documentos do usuário e arquivos pessoais
- Dados de aplicativos (a menos que estejam em diretórios de cache)
- Binários e bibliotecas do sistema
- Arquivos de configuração

## Flags de Linha de Comando

### Flags Comuns (Todos os Scripts)

- `--dry-run, -n`: Visualizar mudanças sem executar
- `--verbose, -v`: Mostrar saída detalhada
- `--quiet, -q`: Suprimir saída não-errônea
- `--help, -h`: Mostrar mensagem de ajuda

### Scripts de Análise de Disco (`analyze-disk.sh`)

- `--items=N`: Mostrar os N maiores itens (padrão: 20)

**Exemplos:**
```bash
./mac/analyze-disk.sh --dry-run
./mac/analyze-disk.sh --items=50 --verbose
```

### Scripts de Limpeza de Disco (`cleanup-disk.sh`)

- `--force, -f`: Pular prompts de confirmação (use com cautela)
- `--min-age=N`: Limpar apenas arquivos mais antigos que N dias (padrão: 0, todos os arquivos)

**Exemplos:**
```bash
./mac/cleanup-disk.sh --dry-run
./mac/cleanup-disk.sh --force --min-age=30
./mac/cleanup-disk.sh --min-age=7  # Apenas arquivos mais antigos que 7 dias
```

### Scripts de Limpeza de Memória (`clean-memory.sh`)

- `--aggressive`: Habilitar modo de limpeza agressiva

| Flag | Descrição | Exemplo |
|------|-----------|---------|
| `--dry-run` | Visualizar mudanças sem executar | `./mac/optimize-all.sh --dry-run` |
| `--aggressive` | Habilitar limpeza agressiva (swap, cache do navegador) | `./mac/clean-memory.sh --aggressive` |
| `--quick` | Modo não interativo (pula confirmações) | `./mac/optimize-all.sh --quick` |
| `--quiet` | Suprimir saída de progresso | `./linux/clean-memory.sh --quiet` |
| `--verbose` | Mostrar logs detalhados | `./mac/optimize-cpu.sh --verbose` |
| `--help` | Mostrar mensagem de ajuda | `./mac/clean-memory.sh --help` |
| `--version` | Mostrar informações de versão | `./linux/optimize-cpu.sh --version` |

## Configuração

### Processos Protegidos

Crie `~/.os-optimize/protected-processes.txt` para personalizar processos protegidos:

```
# Lista de Processos Protegidos
# Um nome de processo por linha
kernel_task
launchd
WindowServer
systemd
```

### Preservação de Cache

Use `--preserve-package-cache` para pular a limpeza de cache do gerenciador de pacotes:

```bash
./linux/clean-memory.sh --preserve-package-cache
```

## Solução de Problemas

### Erros de Permissão

**macOS:**
```bash
# Conceder Acesso Completo ao Disco (Preferências do Sistema > Segurança e Privacidade)
# Ou executar com sudo explícito:
sudo ./mac/optimize-all.sh
```

**Linux:**
```bash
# Garantir acesso sudo:
sudo -v
# Então execute os scripts normalmente
```

### Timeout do Sudo

Se o sudo expirar durante a execução:
```bash
# Atualizar timestamp do sudo
sudo -v
# Executar script novamente
```

### Proteção de Integridade do Sistema (SIP) no macOS

Algumas operações podem ser limitadas pelo SIP. Para verificar o status do SIP:
```bash
csrutil status
```

### SELinux/AppArmor no Linux

Se SELinux/AppArmor bloquear operações:
```bash
# Verificar status do SELinux
getenforce

# Definir temporariamente como permissivo (apenas para testes)
sudo setenforce 0
```

## Diretrizes de Segurança

- ✅ **Faça**: Execute durante tempo ocioso do sistema
- ✅ **Faça**: Use `--dry-run` primeiro
- ✅ **Faça**: Mantenha backups de dados importantes
- ✅ **Faça**: Teste em sistemas não-produção
- ❌ **Não faça**: Execute durante tarefas críticas
- ❌ **Não faça**: Execute em servidores de produção sem testar
- ❌ **Não faça**: Desabilite o SIP no macOS sem entender os riscos

## Como Contribuir

1. Faça um fork do repositório
2. Crie uma branch de feature (`git checkout -b feature/nova-feature`)
3. Faça commit das suas mudanças (`git commit -m 'Adiciona nova feature'`)
4. Faça push para a branch (`git push origin feature/nova-feature`)
5. Abra um Pull Request

### Estilo de Código

- Use `shellcheck` para linting
- Siga a estrutura de código existente
- Adicione comentários para lógica complexa
- Teste em macOS e Linux

## Licença

MIT License - veja o arquivo LICENSE para detalhes

## Créditos

- Inspirado pelas necessidades de otimização de sistema
- Construído com melhores práticas de script bash
- Testado em macOS 12-15 e múltiplas distribuições Linux
