object frmTextDetailsDialog: TfrmTextDetailsDialog
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu, biMaximize]
  BorderStyle = bsSizeable
  Caption = 'Details'
  ClientHeight = 456
  ClientWidth = 720
  Color = clBtnFace
  Constraints.MinHeight = 320
  Constraints.MinWidth = 520
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -13
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  Position = poMainFormCenter
  Scaled = True
  OnCreate = FormCreate
  OnKeyDown = FormKeyDown
  TextHeight = 17
  object pnlContent: TPanel
    Left = 0
    Top = 0
    Width = 720
    Height = 400
    Align = alClient
    BevelOuter = bvNone
    Padding.Left = 16
    Padding.Top = 16
    Padding.Right = 16
    Padding.Bottom = 12
    TabOrder = 0
    object memDetails: TMemo
      Left = 16
      Top = 16
      Width = 688
      Height = 372
      Align = alClient
      Color = clWindow
      ReadOnly = True
      ScrollBars = ssBoth
      TabOrder = 0
      WantReturns = False
      WordWrap = False
    end
  end
  object pnlActions: TPanel
    Left = 0
    Top = 400
    Width = 720
    Height = 56
    Align = alBottom
    BevelOuter = bvNone
    Padding.Left = 16
    Padding.Top = 10
    Padding.Right = 16
    Padding.Bottom = 10
    TabOrder = 1
    object btnClose: TBitBtn
      Left = 616
      Top = 10
      Width = 88
      Height = 36
      Align = alRight
      Cancel = True
      Caption = '&Close'
      ModalResult = 2
      TabOrder = 1
    end
    object btnCopy: TBitBtn
      AlignWithMargins = True
      Left = 517
      Top = 10
      Width = 88
      Height = 36
      Margins.Top = 0
      Margins.Right = 8
      Margins.Bottom = 0
      Align = alRight
      Caption = 'C&opy'
      TabOrder = 0
      OnClick = btnCopyClick
    end
  end
  object DialogButtonImages: TVirtualImageList
    AutoFill = True
    Width = 20
    Height = 20
    Left = 40
    Top = 408
  end
  object DialogButtonSvgCollection: TAdvSVGImageCollection
    Left = 88
    Top = 408
  end
end
