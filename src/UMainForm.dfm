object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'Scan Git Repos'
  ClientHeight = 720
  ClientWidth = 1338
  Color = clWindow
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -13
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 17
  object pnlToolbar: TPanel
    Left = 0
    Top = 0
    Width = 1338
    Height = 68
    Align = alTop
    BevelOuter = bvNone
    Color = clWhitesmoke
    Padding.Left = 16
    Padding.Top = 8
    Padding.Right = 16
    Padding.Bottom = 8
    ParentBackground = False
    TabOrder = 0
    object pnlToolbarContent: TPanel
      Left = 16
      Top = 8
      Width = 1306
      Height = 52
      Align = alClient
      BevelOuter = bvNone
      Color = clWhitesmoke
      ParentBackground = False
      TabOrder = 0
      object pnlRootField: TPanel
        AlignWithMargins = True
        Left = 3
        Top = 3
        Width = 398
        Height = 46
        Margins.Right = 12
        Align = alLeft
        BevelOuter = bvNone
        Color = clWhitesmoke
        ParentBackground = False
        TabOrder = 0
        object edtStartPath: TEdit
          Left = 0
          Top = 20
          Width = 340
          Height = 25
          TabOrder = 0
          TextHint = 'Root Folder'
        end
        object lblStartPath: TStaticText
          Left = 0
          Top = 1
          Width = 340
          Height = 17
          AutoSize = False
          Caption = 'Scan Directory'
          TabOrder = 2
        end
        object btnBrowseStart: TButton
          Left = 348
          Top = 20
          Width = 36
          Height = 25
          Caption = '...'
          TabOrder = 1
          OnClick = btnBrowseStartClick
        end
      end
      object pnlFilterField: TPanel
        AlignWithMargins = True
        Left = 416
        Top = 3
        Width = 240
        Height = 46
        Margins.Right = 12
        Align = alLeft
        BevelOuter = bvNone
        Color = clWhitesmoke
        ParentBackground = False
        TabOrder = 1
        object cboTargetName: TComboBox
          Left = 0
          Top = 20
          Width = 240
          Height = 25
          Style = csDropDownList
          TabOrder = 0
          TextHint = 'Filter by Name'
        end
        object lblTargetName: TStaticText
          Left = 0
          Top = 1
          Width = 240
          Height = 17
          AutoSize = False
          Caption = 'Search Filter'
          TabOrder = 1
        end
      end
      object pnlStatusFilter: TPanel
        AlignWithMargins = True
        Left = 671
        Top = 3
        Width = 190
        Height = 46
        Margins.Right = 12
        Align = alLeft
        BevelOuter = bvNone
        Color = clWhitesmoke
        ParentBackground = False
        TabOrder = 2
        object cboStatusFilter: TComboBox
          Left = 0
          Top = 20
          Width = 181
          Height = 25
          Style = csDropDownList
          TabOrder = 0
          OnChange = cboStatusFilterChange
        end
        object lblStatusFilter: TStaticText
          Left = 0
          Top = 1
          Width = 181
          Height = 17
          AutoSize = False
          Caption = 'Status Filter'
          TabOrder = 1
        end
      end
      object pnlToolbarActions: TPanel
        Left = 891
        Top = 0
        Width = 415
        Height = 52
        Align = alRight
        BevelOuter = bvNone
        Color = clWhitesmoke
        ParentBackground = False
        TabOrder = 3
        object btnScan: TButton
          AlignWithMargins = True
          Left = 302
          Top = 4
          Width = 110
          Height = 44
          Margins.Left = 8
          Margins.Top = 4
          Margins.Bottom = 4
          Align = alRight
          Caption = 'Scan'
          TabOrder = 3
          OnClick = btnScanClick
        end
        object btnSettings: TButton
          AlignWithMargins = True
          Left = 201
          Top = 4
          Width = 90
          Height = 44
          Margins.Top = 4
          Margins.Bottom = 4
          Align = alRight
          Caption = 'Settings'
          TabOrder = 2
          OnClick = btnSettingsClick
        end
        object btnPullVisible: TButton
          AlignWithMargins = True
          Left = 109
          Top = 4
          Width = 86
          Height = 44
          Margins.Top = 4
          Margins.Bottom = 4
          Align = alRight
          Caption = 'Pull all'
          TabOrder = 1
          OnClick = btnPullVisibleClick
        end
        object btnPushVisible: TButton
          AlignWithMargins = True
          Left = 17
          Top = 4
          Width = 86
          Height = 44
          Margins.Top = 4
          Margins.Bottom = 4
          Align = alRight
          Caption = 'Push all'
          TabOrder = 0
          OnClick = btnPushVisibleClick
        end
      end
    end
  end
  object pbProgress: TProgressBar
    AlignWithMargins = True
    Left = 12
    Top = 72
    Width = 1314
    Height = 10
    Margins.Left = 12
    Margins.Top = 4
    Margins.Right = 12
    Margins.Bottom = 0
    Align = alTop
    TabOrder = 5
    Visible = False
  end
  object pnlLogDrawer: TPanel
    Left = 0
    Top = 484
    Width = 1338
    Height = 180
    Align = alBottom
    BevelOuter = bvNone
    Color = clWindow
    ParentBackground = False
    TabOrder = 2
    Visible = False
    object memLog: TMemo
      Left = 0
      Top = 0
      Width = 1338
      Height = 180
      Align = alClient
      BorderStyle = bsNone
      ScrollBars = ssBoth
      TabOrder = 0
      WordWrap = False
    end
  end
  object pnlStatus: TPanel
    AlignWithMargins = True
    Left = 12
    Top = 672
    Width = 1314
    Height = 36
    Margins.Left = 12
    Margins.Top = 8
    Margins.Right = 12
    Margins.Bottom = 12
    Align = alBottom
    BevelOuter = bvNone
    Color = clWhitesmoke
    Padding.Left = 8
    Padding.Top = 4
    Padding.Right = 8
    Padding.Bottom = 4
    ParentBackground = False
    TabOrder = 3
    OnDblClick = pnlStatusDblClick
    object btnShowLog: TButton
      AlignWithMargins = True
      Left = 1216
      Top = 4
      Width = 86
      Height = 28
      Margins.Left = 8
      Margins.Top = 0
      Margins.Right = 4
      Margins.Bottom = 0
      Align = alRight
      Caption = 'Show log'
      TabOrder = 0
      OnClick = btnShowLogClick
    end
    object stsMain: TStatusBar
      AlignWithMargins = True
      Left = 12
      Top = 4
      Width = 1192
      Height = 28
      Margins.Left = 4
      Margins.Top = 0
      Margins.Right = 4
      Margins.Bottom = 0
      Align = alClient
      Panels = <>
      SimplePanel = True
      SimpleText = 'Ready'
      OnDblClick = pnlStatusDblClick
    end
  end
  object pnlSettingsDrawer: TPanel
    Left = 978
    Top = 82
    Width = 360
    Height = 402
    Align = alRight
    BevelOuter = bvNone
    Color = clWindow
    Padding.Left = 16
    Padding.Top = 16
    Padding.Right = 16
    Padding.Bottom = 16
    ParentBackground = False
    TabOrder = 4
    Visible = False
    object lblSettingsHeader: TStaticText
      AlignWithMargins = True
      Left = 19
      Top = 19
      Width = 322
      Height = 24
      Margins.Bottom = 12
      Align = alTop
      AutoSize = False
      Caption = 'Settings'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -19
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
      TabOrder = 0
    end
    object pnlSettingsContent: TPanel
      Left = 16
      Top = 55
      Width = 328
      Height = 331
      Align = alClient
      BevelOuter = bvNone
      Color = clWindow
      ParentBackground = False
      TabOrder = 1
      object pnlMaxDepthField: TPanel
        AlignWithMargins = True
        Left = 3
        Top = 3
        Width = 322
        Height = 60
        Margins.Bottom = 8
        Align = alTop
        BevelOuter = bvNone
        Color = clWindow
        ParentBackground = False
        TabOrder = 0
        DesignSize = (
          322
          60)
        object edtMaxDepth: TEdit
          Left = 0
          Top = 24
          Width = 322
          Height = 25
          Anchors = [akLeft, akTop, akRight]
          TabOrder = 0
        end
        object lblMaxDepth: TStaticText
          Left = 0
          Top = 5
          Width = 322
          Height = 17
          AutoSize = False
          Caption = 'Max depth'
          TabOrder = 1
        end
      end
      object pnlThrottleField: TPanel
        AlignWithMargins = True
        Left = 3
        Top = 74
        Width = 322
        Height = 60
        Margins.Bottom = 8
        Align = alTop
        BevelOuter = bvNone
        Color = clWindow
        ParentBackground = False
        TabOrder = 1
        DesignSize = (
          322
          60)
        object edtThrottle: TEdit
          Left = 0
          Top = 24
          Width = 322
          Height = 25
          Anchors = [akLeft, akTop, akRight]
          TabOrder = 0
        end
        object lblThrottle: TStaticText
          Left = 0
          Top = 5
          Width = 322
          Height = 17
          AutoSize = False
          Caption = 'Parallel Processing Limit'
          TabOrder = 1
        end
      end
      object pnlCacheField: TPanel
        AlignWithMargins = True
        Left = 3
        Top = 145
        Width = 322
        Height = 60
        Margins.Bottom = 8
        Align = alTop
        BevelOuter = bvNone
        Color = clWindow
        ParentBackground = False
        TabOrder = 2
        DesignSize = (
          322
          60)
        object edtCacheTtl: TEdit
          Left = 0
          Top = 24
          Width = 322
          Height = 25
          Anchors = [akLeft, akTop, akRight]
          TabOrder = 0
        end
        object lblCacheTtl: TStaticText
          Left = 0
          Top = 5
          Width = 322
          Height = 17
          AutoSize = False
          Caption = 'Refresh Interval'
          TabOrder = 1
        end
      end
      object pnlIgnoreDirs: TPanel
        AlignWithMargins = True
        Left = 3
        Top = 216
        Width = 322
        Height = 54
        Margins.Bottom = 8
        Align = alTop
        BevelOuter = bvNone
        Color = clWindow
        ParentBackground = False
        TabOrder = 3
        object lblIgnoreDirs: TStaticText
          Left = 0
          Top = 0
          Width = 322
          Height = 17
          AutoSize = False
          Caption = 'Ignore directory rules'
          TabOrder = 1
        end
        object btnEditIgnoreDirs: TButton
          Left = 0
          Top = 24
          Width = 150
          Height = 28
          Caption = 'Edit ignore rules'
          TabOrder = 0
          OnClick = btnEditIgnoreDirsClick
        end
      end
      object chkDebugLog: TCheckBox
        AlignWithMargins = True
        Left = 3
        Top = 281
        Width = 322
        Height = 21
        Margins.Bottom = 8
        Align = alTop
        Caption = 'Debug log'
        TabOrder = 4
      end
      object pnlDebugPathField: TPanel
        AlignWithMargins = True
        Left = 3
        Top = 313
        Width = 322
        Height = 60
        Margins.Bottom = 8
        Align = alTop
        BevelOuter = bvNone
        Color = clWindow
        ParentBackground = False
        TabOrder = 5
        DesignSize = (
          322
          60)
        object edtDebugLogPath: TEdit
          Left = 0
          Top = 24
          Width = 322
          Height = 25
          Anchors = [akLeft, akTop, akRight]
          TabOrder = 0
        end
        object lblDebugLogPath: TStaticText
          Left = 0
          Top = 5
          Width = 322
          Height = 17
          AutoSize = False
          Caption = 'Debug log path'
          TabOrder = 1
        end
      end
    end
  end
  object sbRepos: TScrollBox
    Left = 0
    Top = 82
    Width = 978
    Height = 402
    Align = alClient
    BorderStyle = bsNone
    TabOrder = 1
    OnResize = sbReposResize
    object fpRepos: TFlowPanel
      Left = 0
      Top = 0
      Width = 978
      Height = 41
      Align = alTop
      AutoSize = True
      AutoWrap = False
      BevelOuter = bvNone
      Color = clWindow
      FlowStyle = fsTopBottomLeftRight
      Padding.Left = 16
      Padding.Top = 12
      Padding.Right = 16
      Padding.Bottom = 12
      ParentBackground = False
      TabOrder = 0
    end
  end
  object tmrUi: TTimer
    Interval = 100
    OnTimer = tmrUiTimer
    Left = 1112
    Top = 16
  end
  object pmRepoActions: TPopupMenu
    Left = 1048
    Top = 16
    object miRepoCommit: TMenuItem
      Caption = 'Commit'
      OnClick = RepoMenuClick
    end
    object miRepoFetch: TMenuItem
      Caption = 'Fetch'
      OnClick = RepoMenuClick
    end
    object miRepoFixSubmoduleMain: TMenuItem
      Caption = 'Fix submodule to remote main'
      OnClick = RepoMenuClick
    end
    object miRepoOpenFolder: TMenuItem
      Caption = 'Open folder'
      OnClick = RepoMenuClick
    end
  end
end
