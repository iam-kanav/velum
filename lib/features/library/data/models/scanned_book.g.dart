// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scanned_book.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ScannedBookAdapter extends TypeAdapter<ScannedBook> {
  @override
  final int typeId = 0;

  @override
  ScannedBook read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ScannedBook(
      filePath: fields[0] as String,
      title: fields[1] as String,
      author: fields[2] as String,
      addedAt: fields[3] as DateTime?,
      coverBase64: fields[4] as String?,
      isPinned: fields[5] as bool,
      lastReadTime: fields[6] as DateTime?,
      lastReadChapter: fields[7] as int?,
      lastReadPosition: fields[8] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, ScannedBook obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.filePath)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.author)
      ..writeByte(3)
      ..write(obj.addedAt)
      ..writeByte(4)
      ..write(obj.coverBase64)
      ..writeByte(5)
      ..write(obj.isPinned)
      ..writeByte(6)
      ..write(obj.lastReadTime)
      ..writeByte(7)
      ..write(obj.lastReadChapter)
      ..writeByte(8)
      ..write(obj.lastReadPosition);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScannedBookAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
