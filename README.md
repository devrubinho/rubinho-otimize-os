# OS Optimization Scripts

🇺🇸 [English](#english) | 🇧🇷 [Português](#português)

---

<a id="english"></a>
# English

## Project Overview

A cross-platform OS optimization toolkit that helps users clean and optimize system resources when their computer is running slow. This project provides dedicated optimization scripts for macOS and Linux operating systems.

## ⚠️ Warning

<div style="background-color: #fff3cd; border-left: 4px solid #ffc107; padding: 12px; margin: 16px 0;">

**Use with caution!** These scripts perform system-level operations that can affect your computer's performance and stability. Always:

- Run with `--dry-run` first to preview changes
- Ensure you have backups of important data
- Close critical applications before running
- Test on non-production systems first

</div>

## Prerequisites

- **macOS**: 10.13+ (High Sierra or later)
- **Linux**: Ubuntu 20.04+, Fedora 36+, Debian 11+, or Arch Linux
- **Bash**: 4.0+ (check with `bash --version`)
- **Sudo access**: Required for system-level operations
- **Disk space**: At least 5GB free recommended

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/rubinho-otimize-os.git
cd rubinho-otimize-os
```

2. Run the installation script:
```bash
./install.sh
```

3. Set executable permissions (if needed):
```bash
chmod +x mac/*.sh linux/*.sh install.sh
```

4. Verify installation:
```bash
./mac/optimize-all.sh --help
./linux/optimize-all.sh --help
```

## Usage

### Quick Start

**macOS:**
```bash
# Preview changes (recommended first)
./mac/optimize-all.sh --dry-run

# Run full optimization
./mac/optimize-all.sh

# Quick mode (non-interactive)
./mac/optimize-all.sh --quick
```

**Linux:**
```bash
# Preview changes (recommended first)
./linux/optimize-all.sh --dry-run

# Run full optimization
./linux/optimize-all.sh

# Scheduled mode (for cron)
./linux/optimize-all.sh --scheduled
```

### Individual Scripts

**Memory Cleaning:**
```bash
# macOS
./mac/clean-memory.sh --dry-run
./mac/clean-memory.sh --aggressive

# Linux
./linux/clean-memory.sh --dry-run
./linux/clean-memory.sh --cache-level 3
```

**CPU Optimization:**
```bash
# macOS
./mac/optimize-cpu.sh --dry-run
./mac/optimize-cpu.sh --process-threshold 50

# Linux
./linux/optimize-cpu.sh --dry-run
./linux/optimize-cpu.sh --process-threshold 30
```

## Script Descriptions

### macOS Scripts

#### `clean-memory.sh`
- Clears inactive memory using `purge`
- Purges disk cache
- Clears DNS and font caches
- Cleans user and system caches
- **Execution time**: ~30-60 seconds
- **Typical memory freed**: 2-8 GB

#### `optimize-cpu.sh`
- Identifies CPU-intensive processes
- Safe process termination (protects critical processes)
- System log cleanup (ASL and unified logs)
- Spotlight indexing check
- Launch daemon audit
- **Execution time**: ~20-40 seconds

#### `optimize-all.sh`
- Orchestrates all optimization tasks
- Progress indicators
- Comprehensive JSON reports
- System snapshots and rollback checkpoints
- **Execution time**: ~60-120 seconds

### Linux Scripts

#### `clean-memory.sh`
- Drops page cache, dentries, and inodes
- Swap management (clear if usage >50%)
- Package manager cache cleanup (apt/dnf/pacman)
- Systemd journal vacuum (keep last 7 days)
- Thumbnail cache cleanup
- **Execution time**: ~20-50 seconds
- **Typical memory freed**: 1-4 GB

#### `optimize-cpu.sh`
- CPU usage monitoring
- Process management with safe-kill protection
- System log rotation and cleanup
- Zombie process detection
- Systemd service audit
- **Execution time**: ~30-60 seconds

#### `optimize-all.sh`
- Full optimization workflow
- Distribution detection
- System snapshot capture
- JSON report generation
- Email notifications (optional)
- **Execution time**: ~60-150 seconds

## Command-Line Flags

| Flag | Description | Example |
|------|-------------|---------|
| `--dry-run` | Preview changes without executing | `./mac/optimize-all.sh --dry-run` |
| `--aggressive` | Enable aggressive cleaning (swap, browser cache) | `./mac/clean-memory.sh --aggressive` |
| `--quick` | Non-interactive mode (skip confirmations) | `./mac/optimize-all.sh --quick` |
| `--quiet` | Suppress progress output | `./linux/clean-memory.sh --quiet` |
| `--verbose` | Show detailed logs | `./mac/optimize-cpu.sh --verbose` |
| `--help` | Show help message | `./mac/clean-memory.sh --help` |
| `--version` | Show version information | `./linux/optimize-cpu.sh --version` |

## Configuration

### Protected Processes

Create `~/.os-optimize/protected-processes.txt` to customize protected processes:

```
# Protected Processes Whitelist
# One process name per line
kernel_task
launchd
WindowServer
systemd
```

### Cache Preservation

Use `--preserve-package-cache` to skip package manager cache cleanup:

```bash
./linux/clean-memory.sh --preserve-package-cache
```

## Troubleshooting

### Permission Errors

**macOS:**
```bash
# Grant Full Disk Access (System Preferences > Security & Privacy)
# Or run with explicit sudo:
sudo ./mac/optimize-all.sh
```

**Linux:**
```bash
# Ensure sudo access:
sudo -v
# Then run scripts normally
```

### Sudo Timeout

If sudo times out during execution:
```bash
# Refresh sudo timestamp
sudo -v
# Run script again
```

### macOS System Integrity Protection (SIP)

Some operations may be limited by SIP. To check SIP status:
```bash
csrutil status
```

### Linux SELinux/AppArmor

If SELinux/AppArmor blocks operations:
```bash
# Check SELinux status
getenforce

# Temporarily set to permissive (for testing only)
sudo setenforce 0
```

## Safety Guidelines

- ✅ **Do**: Run during system idle time
- ✅ **Do**: Use `--dry-run` first
- ✅ **Do**: Keep backups of important data
- ✅ **Do**: Test on non-production systems
- ❌ **Don't**: Run during critical tasks
- ❌ **Don't**: Run on production servers without testing
- ❌ **Don't**: Disable SIP on macOS without understanding risks

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Code Style

- Use `shellcheck` for linting
- Follow existing code structure
- Add comments for complex logic
- Test on both macOS and Linux

## License

MIT License - see LICENSE file for details

## Credits

- Inspired by system optimization needs
- Built with bash scripting best practices
- Tested on macOS 12-15 and multiple Linux distributions

---

<a id="português"></a>
# Português

## Visão Geral do Projeto

Um kit de ferramentas de otimização de sistema multiplataforma que ajuda os usuários a limpar e otimizar recursos do sistema quando o computador está lento. Este projeto fornece scripts de otimização dedicados para macOS e Linux.

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
git clone https://github.com/yourusername/rubinho-otimize-os.git
cd rubinho-otimize-os
```

2. Execute o script de instalação:
```bash
./install.sh
```

3. Defina permissões de execução (se necessário):
```bash
chmod +x mac/*.sh linux/*.sh install.sh
```

4. Verifique a instalação:
```bash
./mac/optimize-all.sh --help
./linux/optimize-all.sh --help
```

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

## Flags de Linha de Comando

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
