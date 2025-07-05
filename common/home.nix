{
  lib,
  config,
  pkgs,
  nixvim,
  ...
}:

{
  home.username = "amjad";
  home.homeDirectory = "/home/amjad";
  home.stateVersion = "25.05";

  # User packages
  home.packages = with pkgs; [
    # Core development tools
    delta

    # Shell utilities
    fzf
    ripgrep
    bat
    eza
    zoxide
    yazi

    # Development environments
    cargo
  ];

  # Git configuration
  programs.git = {
    enable = true;
    userName = "Amjad Alsharafi";
    userEmail = "26300843+Amjad50@users.noreply.github.com";

    # Git aliases
    aliases = {
      st = "status";
      ch = "checkout";
      br = "branch";
      logg = "log --oneline --full-history --all --decorate --graph";
      d = "diff";
      ds = "diff --staged";
    };

    signing = {
      format = "openpgp";
      signByDefault = true;
    };

    delta = {
      enable = true;
      options = {
        navigate = true;
        sideBySide = false;
      };
    };

    lfs.enable = true;

    extraConfig = {
      # Include private config
      # include.path = "~/.gitconfig.local";

      # Core settings
      core = {
        editor = "nvim";
        filemode = false;
        autocrlf = "input";
      };

      # Delta configuration
      delta = {
        navigate = true;
        side-by-side = false;
      };

      # Diff settings
      diff = {
        tool = "nvimdiff";
        algorithm = "histogram";
      };

      # Merge settings
      merge = {
        conflictstyle = "diff3";
      };

      commit = {
        verbose = true;
      };

      # Init settings
      init = {
        defaultBranch = "master";
      };

      # Format settings
      format = {
        signOff = true;
      };

      # Color settings
      color = {
        ui = "auto";
      };

      # Git LFS
      filter."lfs" = {
        clean = "git-lfs clean -- %f";
        smudge = "git-lfs smudge -- %f";
        process = "git-lfs filter-process";
        required = true;
      };
    };
  };

  # Zsh configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion = {
      enable = true;
      strategy = [
        "history"
        "completion"
      ];
    };
    syntaxHighlighting.enable = true;
    historySubstringSearch.enable = true;

    # Environment variables
    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      HISTCONTROL = "ignoreboth:erasedups";
      GPG_TTY = "$(tty)";
    };

    history = {
      size = 100000;
      append = true;
      share = true;
      ignoreDups = true;
      path = "$HOME/.zsh_history";
    };

    defaultKeymap = "emacs";

    autocd = true;

    # Aliases from your zshrc
    shellAliases = {
      # Basic ls aliases
      ls = "ls --color=auto";
      la = "ls -a";
      ll = "ls -lah";
      l = "ls";
      "l." = "ls -A | egrep '^\\.'";

      # Navigation
      ".." = "cd ..";
      "cd.." = "cd ..";
      pdw = "pwd";

      # Grep with color
      grep = "grep --color=auto";
      egrep = "egrep --color=auto";
      fgrep = "fgrep --color=auto";

      # System utilities
      df = "df -h";
      free = "free -mt";
      wget = "wget -c";

      # Process management
      psa = "ps auxf";
      psgrep = "ps aux | grep -v grep | grep -i -e VSZ -e";

      # Search and navigation
      rg = "rg --sort path";

      # Journalctl
      jctl = "journalctl -p 3 -xb";

      # System control
      ssn = "sudo shutdown now";
      sr = "sudo reboot";

      # File operations
      userlist = "cut -d: -f1 /etc/passwd";
    };

    initContent = ''
      # Enable p10k
      [[ ! -f $HOME/.p10k.zsh ]] || source $HOME/.p10k.zsh

      # helper functions
      y() {
        local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
        yazi "$@" --cwd-file="$tmp"
        if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
          builtin cd -- "$cwd"
        fi
        rm -f -- "$tmp"
      }

      activate_venv() {
        source ./venv/bin/activate
      }

      ex() {
        if [ -f $1 ]; then
          case $1 in
            *.tar.bz2)   tar xjf $1   ;;
            *.tar.gz)    tar xzf $1   ;;
            *.bz2)       bunzip2 $1   ;;
            *.rar)       unrar x $1   ;;
            *.gz)        gunzip $1    ;;
            *.tar)       tar xf $1    ;;
            *.tbz2)      tar xjf $1   ;;
            *.tgz)       tar xzf $1   ;;
            *.zip)       unzip $1     ;;
            *.Z)         uncompress $1;;
            *.7z)        7z x $1      ;;
            *.deb)       ar x $1      ;;
            *.tar.xz)    tar xf $1    ;;
            *.tar.zst)   tar xf $1    ;;
            *)           echo "'$1' cannot be extracted via ex()" ;;
          esac
        else
          echo "'$1' is not a valid file"
        fi
      }

      rga-fzf() {
        RG_PREFIX="rga --files-with-matches"
        local file
        file="$(
          FZF_DEFAULT_COMMAND="$RG_PREFIX '$1'" \
            fzf --sort --preview="[[ ! -z {} ]] && rga --pretty --context 5 {q} {}" \
              --phony -q "$1" \
              --bind "change:reload:$RG_PREFIX {q}" \
              --preview-window="70%:wrap"
        )" &&
        echo "opening $file" &&
        xdg-open "$file"
      }

      bindkey "^[[3~" delete-char
    '';

    # Zsh plugins via zinit (managed in initExtra)
    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  # FZF configuration
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "rg --files";
    changeDirWidgetCommand = "fd --type d";
    changeDirWidgetOptions = [ "--preview 'tree -C {} | head -200'" ];
    fileWidgetCommand = "rg --files";
    fileWidgetOptions = [ "--preview 'head {}'" ];
    historyWidgetOptions = [
      "--sort"
      "--exact"
    ];
  };

  # Bat configuration
  programs.bat = {
    enable = true;
    config = {
      pager = "less -RF";
      theme = "TwoDark";
    };
  };

  programs.nixvim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    defaultEditor = true;

    # VSCode colorscheme
    colorschemes.vscode = {
      enable = true;
      settings = {
        transparent = true;
        italic_comments = true;
        disable_nvimtree_bg = true;
        color_overrides = {
          vscLineNumber = "#eeeeee";
        };
      };
    };

    # Global options
    opts = {
      encoding = "utf-8";
      termguicolors = true;
      showmode = false;

      # Line numbers
      number = true;
      relativenumber = true;

      # Indentation
      expandtab = true;
      smarttab = true;
      smartindent = true;
      shiftwidth = 4;
      tabstop = 4;
      softtabstop = 4;

      # Search
      incsearch = true;
      smartcase = true;
      hlsearch = true;
      gdefault = true;

      # Splits
      splitright = true;
      splitbelow = true;

      # Completion
      completeopt = "menuone,noinsert,noselect";

      # UI
      signcolumn = "yes";
      wildmenu = true;
      updatetime = 200;
      listchars = "nbsp:¬,extends:»,precedes:«,trail:•";
      mouse = "a";

      # Folding (for nvim-ufo)
      fillchars = "eob: ,fold: ,foldopen:,foldsep: ,foldclose:";
      foldcolumn = "1";
      foldlevel = 99;
      foldlevelstart = 99;
      foldenable = true;
    };

    # Auto commands
    autoCmd = [
      {
        event = "FileType";
        pattern = "gitcommit";
        command = "set spell";
      }
    ];

    # Treesitter syntax highlighting
    plugins.treesitter = {
      enable = true;
      grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        bash
        c
        cpp
        css
        html
        javascript
        typescript
        json
        lua
        python
        rust
        yaml
        toml
        swift
        zig
        glsl
        markdown
        nix
        vim
      ];
      settings = {
        highlight = {
          enable = true;
          additional_vim_regex_highlighting = false;
        };
        incremental_selection.enable = true;
      };
    };

    # Treesitter context
    plugins.treesitter-context = {
      enable = true;
      settings = {
        max_lines = 3;
      };
    };

    # LSP configuration
    # plugins.lsp = {
    #   enable = true;
    #   servers = {
    #     rust_analyzer = {
    #       enable = true;
    #       installCargo = true;
    #       installRustc = true;
    #     };
    #     pyright.enable = true;
    #     tsserver.enable = true;
    #     lua_ls.enable = true;
    #     nil_ls.enable = true; # Nix LSP
    #   };
    # };

    # # Auto completion
    # plugins.cmp = {
    #   enable = true;
    #   settings = {
    #     snippet.expand = "function(args) vim.fn['vsnip#anonymous'](args.body) end";
    #     sources = [
    #       { name = "nvim_lsp"; }
    #       { name = "vsnip"; }
    #       { name = "buffer"; }
    #       { name = "path"; }
    #       { name = "nvim_lsp_signature_help"; }
    #     ];
    #     mapping = {
    #       "<C-d>" = "cmp.mapping.scroll_docs(-4)";
    #       "<C-f>" = "cmp.mapping.scroll_docs(4)";
    #       "<C-Space>" = "cmp.mapping.complete()";
    #       "<C-e>" = "cmp.mapping.close()";
    #       "<Tab>" = "cmp.mapping(cmp.mapping.select_next_item(), {'i', 's'})";
    #       "<S-Tab>" = "cmp.mapping(cmp.mapping.select_prev_item(), {'i', 's'})";
    #       "<CR>" = "cmp.mapping.confirm({ select = true })";
    #     };
    #   };
    # };

    # Snippet support
    # plugins.vsnip.enable = true;

    # File explorer
    # plugins.nvim-tree = {
    #   enable = true;
    #   disableNetrw = true;
    #   hijackNetrw = true;
    #   openOnSetup = true;
    #   view = {
    #     side = "left";
    #     width = 30;
    #   }
    # };

    # Telescope fuzzy finder
    plugins.telescope = {
      enable = true;
      extensions = {
        fzf-native.enable = true;
        file-browser = {
          enable = true;
          settings.hijack_netrw = true;
        };
      };
      settings = {
        defaults = {
          path_display = {
            shorten = {
              len = 5;
            };
          };
        };
      };
    };

    # Git integration
    plugins.gitsigns = {
      enable = true;
      settings = {
        current_line_blame = true;
        current_line_blame_opts = {
          virt_text = true;
          virt_text_pos = "eol";
          delay = 1000;
          ignore_whitespace = true;
        };
      };
    };

    # Status line (using lualine instead of galaxyline)
    plugins.lualine = {
      enable = true;
      # settings = {
      #   options = {
      #     theme = "vscode";
      #     component_separators = { left = ""; right = ""; };
      #     section_separators = { left = ""; right = ""; };
      #   };
      # };
    };

    # Buffer line
    plugins.bufferline = {
      enable = true;
      settings = {
        options = {
          right_mouse_command = "";
          middle_mouse_command = "bdelete! %d";
          diagnostics = "nvim_lsp";
          diagnostics_update_in_insert = false;
        };
      };
    };

    # LSP status
    plugins.fidget = {
      enable = true;
      settings = { };
    };

    # Diagnostics
    plugins.trouble = {
      enable = true;
      settings = { };
    };

    # TODO comments
    plugins.todo-comments = {
      enable = true;
      settings = { };
    };

    # Movement with leap
    plugins.leap = {
      enable = true;
    };

    # # Rust-specific tools
    # plugins.rustaceanvim = {
    #   enable = true;
    #   settings = {};
    # };

    # # Crates.nvim for Cargo.toml
    # plugins.crates-nvim = {
    #   enable = true;
    #   settings = {};
    # };

    # Web dev icons
    plugins.web-devicons.enable = true;

    # Folding with nvim-ufo
    plugins.nvim-ufo = {
      enable = true;
      settings = { };
    };

    # UI improvements
    plugins.dressing = {
      enable = true;
      settings = { };
    };
  };

  # Let Home Manager install and manage itself
  programs.home-manager.enable = true;
}
