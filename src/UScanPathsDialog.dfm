object frmScanPathsDialog: TfrmScanPathsDialog
  Left = 0
  Top = 0
  Caption = 'Edit Scan Paths'
  BorderStyle = bsDialog
  ClientHeight = 400
  ClientWidth = 680
  Color = clWindow
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
  object memPaths: TMemo
    AlignWithMargins = True
    Left = 16
    Top = 44
    Width = 648
    Height = 298
    Margins.Left = 0
    Margins.Top = 8
    Margins.Right = 0
    Margins.Bottom = 8
    Align = alClient
    ScrollBars = ssBoth
    TabOrder = 0
    WordWrap = False
  end
  object lblInstructions: TStaticText
    Left = 16
    Top = 16
    Width = 648
    Height = 20
    Align = alTop
    AutoSize = False
    Caption = '&Scan paths (one existing folder per line)'
    FocusControl = memPaths
    TabOrder = 1
  end
  object pnlActions: TPanel
    Left = 16
    Top = 350
    Width = 648
    Height = 34
    Align = alBottom
    BevelOuter = bvNone
    ParentBackground = False
    TabOrder = 2
    DesignSize = (
      648
      34)
    object btnAddFolder: TButton
      Left = 0
      Top = 3
      Width = 110
      Height = 27
      Caption = '&Add folder...'
      TabOrder = 0
      OnClick = btnAddFolderClick
    end
    object btnCancel: TButton
      Left = 456
      Top = 3
      Width = 90
      Height = 27
      Anchors = [akTop, akRight]
      Cancel = True
      Caption = '&Cancel'
      ModalResult = 2
      TabOrder = 1
    end
    object btnOk: TButton
      Left = 558
      Top = 3
      Width = 90
      Height = 27
      Anchors = [akTop, akRight]
      Caption = '&Save'
      Default = True
      TabOrder = 2
      OnClick = btnOkClick
    end
  end
end
