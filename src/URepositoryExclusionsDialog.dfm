object RepositoryExclusionsDialog: TRepositoryExclusionsDialog
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu, biMaximize]
  Caption = 'Repository exclusions'
  ClientHeight = 520
  ClientWidth = 720
  Color = clWindow
  Constraints.MinHeight = 400
  Constraints.MinWidth = 560
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -13
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  Padding.Left = 16
  Padding.Top = 16
  Padding.Right = 16
  Padding.Bottom = 16
  Position = poOwnerFormCenter
  TextHeight = 17
  object pnlRules: TPanel
    Left = 16
    Top = 16
    Width = 688
    Height = 220
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object memPatterns: TMemo
      AlignWithMargins = True
      Left = 0
      Top = 25
      Width = 688
      Height = 161
      Margins.Left = 0
      Margins.Top = 8
      Margins.Right = 0
      Margins.Bottom = 8
      Align = alClient
      ScrollBars = ssBoth
      TabOrder = 0
      WantTabs = False
      WordWrap = False
      OnChange = memPatternsChange
    end
    object lblPatterns: TStaticText
      Left = 0
      Top = 0
      Width = 688
      Height = 17
      Align = alTop
      Caption = '&Exclusion patterns (one per line)'
      FocusControl = memPatterns
      TabOrder = 1
    end
    object lblHelp: TStaticText
      Left = 0
      Top = 194
      Width = 688
      Height = 26
      Align = alBottom
      AutoSize = False
      Caption = '* matches any text; ? matches one character. Blank lines are ignored.'
      TabOrder = 2
    end
  end
  object pnlPreview: TPanel
    Left = 16
    Top = 236
    Width = 688
    Height = 230
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 1
    object lstPreview: TListBox
      AlignWithMargins = True
      Left = 0
      Top = 25
      Width = 688
      Height = 197
      Margins.Left = 0
      Margins.Top = 8
      Margins.Right = 0
      Margins.Bottom = 8
      Align = alClient
      ItemHeight = 17
      TabOrder = 0
    end
    object lblPreview: TStaticText
      Left = 0
      Top = 0
      Width = 688
      Height = 17
      Align = alTop
      Caption = '&Preview: 0 known repositories would be hidden'
      FocusControl = lstPreview
      TabOrder = 1
    end
  end
  object pnlActions: TPanel
    Left = 16
    Top = 466
    Width = 688
    Height = 38
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 2
    object btnCancel: TBitBtn
      AlignWithMargins = True
      Left = 484
      Top = 4
      Width = 96
      Height = 30
      Margins.Left = 8
      Margins.Top = 4
      Margins.Right = 0
      Margins.Bottom = 4
      Align = alRight
      Cancel = True
      Caption = '&Cancel'
      ModalResult = 2
      TabOrder = 0
    end
    object btnApply: TBitBtn
      AlignWithMargins = True
      Left = 592
      Top = 4
      Width = 96
      Height = 30
      Margins.Left = 8
      Margins.Top = 4
      Margins.Right = 0
      Margins.Bottom = 4
      Align = alRight
      Caption = '&Apply'
      Default = True
      ModalResult = 1
      TabOrder = 1
    end
  end
end
