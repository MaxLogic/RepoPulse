object frmStatusFilterHelp: TfrmStatusFilterHelp
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  Caption = 'Status Filter Help'
  ClientHeight = 436
  ClientWidth = 640
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -13
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  Position = poOwnerFormCenter
  Scaled = True
  OnCreate = FormCreate
  OnKeyDown = FormKeyDown
  TextHeight = 17
  object pnlContent: TPanel
    Left = 0
    Top = 0
    Width = 640
    Height = 380
    Align = alClient
    BevelOuter = bvNone
    Padding.Left = 16
    Padding.Top = 16
    Padding.Right = 16
    Padding.Bottom = 12
    TabOrder = 0
    object memStatusFilterHelp: TMemo
      Left = 16
      Top = 16
      Width = 608
      Height = 352
      Align = alClient
      BorderStyle = bsNone
      Color = clWindow
      Lines.Strings = (
        'Needs attention: any Git, scan, Pull, or Push problem.'
        ''
        'Operation failed: the last Pull or Push failed during this application session.'
        ''
        'Scan failed: repository status could not be scanned.'
        ''
        'Unrelated history: HEAD and upstream have no common ancestor; ahead/behind counts are suppressed and Pull all is disabled.'
        ''
        'Safe pull: clean and behind - behind, not ahead, and without dirty files.'
        ''
        'Behind, not ahead - behind and not ahead; includes dirty and detached repositories.'
        ''
        'Diverged: both ahead and behind.'
        ''
        'Ahead, not behind - ahead by at least one commit and not behind.'
        ''
        'Dirty: has local working-tree changes.'
        ''
        'Detached: HEAD is detached.'
        ''
        'No issues: none of the Needs attention conditions apply.'
        ''
        'All: every discovered repository, including waiting and failed rows.')
      ReadOnly = True
      ScrollBars = ssVertical
      TabOrder = 0
      WantReturns = False
      WordWrap = True
    end
  end
  object pnlActions: TPanel
    Left = 0
    Top = 380
    Width = 640
    Height = 56
    Align = alBottom
    BevelOuter = bvNone
    Padding.Left = 16
    Padding.Top = 10
    Padding.Right = 16
    Padding.Bottom = 10
    TabOrder = 1
    object btnClose: TBitBtn
      Left = 536
      Top = 10
      Width = 88
      Height = 36
      Align = alRight
      Cancel = True
      Caption = '&Close'
      ModalResult = 2
      TabOrder = 0
    end
  end
  object DialogButtonImages: TVirtualImageList
    AutoFill = True
    Width = 20
    Height = 20
    Left = 40
    Top = 388
  end
  object DialogButtonSvgCollection: TAdvSVGImageCollection
    Left = 88
    Top = 388
  end
end
