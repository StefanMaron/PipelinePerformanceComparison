/// <summary>
/// Sample data line table for performance testing
/// </summary>
table 50001 "Sample Data Line PPC"
{
    Caption = 'Sample Data Line';
    DataClassification = CustomerContent;
    
    fields
    {
        field(1; "Document No."; Code[20])
        {
            Caption = 'Document No.';
            TableRelation = "Sample Data PPC"."Code";
        }
        
        field(2; "Line No."; Integer)
        {
            Caption = 'Line No.';
        }
        
        field(10; "Item Code"; Code[20])
        {
            Caption = 'Item Code';
        }
        
        field(20; "Description"; Text[100])
        {
            Caption = 'Description';
        }
        
        field(30; "Quantity"; Decimal)
        {
            Caption = 'Quantity';
            DecimalPlaces = 0 : 5;
        }
        
        field(40; "Unit Price"; Decimal)
        {
            Caption = 'Unit Price';
            DecimalPlaces = 2 : 5;
        }
        
        field(50; "Amount"; Decimal)
        {
            Caption = 'Amount';
            DecimalPlaces = 2 : 5;
        }
    }
    
    keys
    {
        key(PK; "Document No.", "Line No.")
        {
            Clustered = true;
        }
    }
    
    trigger OnValidate()
    begin
        Amount := Quantity * "Unit Price";
    end;
}