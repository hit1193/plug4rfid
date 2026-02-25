import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../models/devices.dart';

class DevicePage extends StatelessWidget {
  final List<Device> list;
  final String searchQuery;
  final bool isMobile;
  final Function(Device?) onEdit;

  const DevicePage({
    super.key,
    required this.list,
    required this.searchQuery,
    required this.isMobile,
    required this.onEdit,
  });

  IconData _getDeviceIcon(String type) {
    switch (type) {
      case 'RFID': return FontAwesomeIcons.rss;
      case 'Printer': return FontAwesomeIcons.print;
      case 'Barcode-Scanner': return FontAwesomeIcons.barcode;
      default: return FontAwesomeIcons.cube;
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Device> filtered = list;
    if (searchQuery.isNotEmpty) {
      filtered = list.where((d) => d.name.toLowerCase().contains(searchQuery.toLowerCase()) || d.ipAddress.contains(searchQuery)).toList();
    }

    if (filtered.isEmpty) return const Center(child: Text("결과가 없습니다."));

    if (isMobile) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
        itemCount: filtered.length,
        itemBuilder: (context, index) => _buildCard(filtered[index]),
      );
    }
    return _buildTable(filtered);
  }

  Widget _buildTable(List<Device> list) {
    return Container(
      margin: const EdgeInsets.fromLTRB(26, 0, 26, 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: MaterialStateProperty.all(Colors.indigo.withOpacity(0.05)),
            showCheckboxColumn: false,
            columns: const [DataColumn(label: Text('종류')), DataColumn(label: Text('장치명')), DataColumn(label: Text('통신방식')), DataColumn(label: Text('모델')), DataColumn(label: Text('IP/Port')), DataColumn(label: Text('상태')), DataColumn(label: Text('관리'))],
            rows: list.map((item) {
              bool isOnline = item.status == 'Online';
              return DataRow(onSelectChanged: (s) => onEdit(item), cells: [
                DataCell(Row(children: [FaIcon(_getDeviceIcon(item.type), size: 14, color: Colors.indigo), const SizedBox(width: 8), Text(item.type)])),
                DataCell(Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                DataCell(Text(item.commMethod)),
                DataCell(Text(item.model)),
                DataCell(Text(item.ipAddress)),
                DataCell(Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: isOnline ? Colors.green : Colors.red, shape: BoxShape.circle)), const SizedBox(width: 8), Text(item.status, style: TextStyle(color: isOnline ? Colors.green : Colors.red, fontWeight: FontWeight.bold))])),
                DataCell(IconButton(icon: const Icon(Icons.settings, size: 18), onPressed: () => onEdit(item))),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(Device item) {
    bool isOnline = item.status == 'Online';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        leading: FaIcon(_getDeviceIcon(item.type), color: isOnline ? Colors.indigo : Colors.grey),
        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("${item.type} | ${item.commMethod}"),
        trailing: Icon(Icons.circle, size: 12, color: isOnline ? Colors.green : Colors.red),
        onTap: () => onEdit(item),
      ),
    );
  }
}