import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';

import '../services/pb_service.dart';
import '../models/persons.dart';
import '../models/products.dart';
import '../widgets/stat_card.dart';
import 'kiosk_view.dart';
import 'person_page.dart';
import 'device_page.dart';
import 'product_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  bool _isKioskMode = true;
  int _selectedIndex = 3;
  bool isLoading = false;

  final String _pbBaseUrl = "http://127.0.0.1:8090";

  List<Person> personList = [];
  List<ProductModel> productList = [];

  @override
  void initState() {
    super.initState();
    _fetchSummaryData();
    _subscribeSummary();
  }

  Future<void> _fetchSummaryData() async {
    try {
      final pRecords = await PBService.pb.collection('persons').getFullList();
      final prodRecords = await PBService.pb.collection('products').getFullList();

      if (mounted) {
        setState(() {
          personList = pRecords.map((r) => Person.fromRecord(r)).toList();
          productList = prodRecords.map((r) => ProductModel.fromJson(r.toJson())).toList();
        });
      }
    } catch (e) {
      debugPrint("데이터 로드 중 오류 발생: $e");
    }
  }

  void _subscribeSummary() {
    PBService.pb.collection('persons').subscribe('*', (e) => _fetchSummaryData());
    PBService.pb.collection('products').subscribe('*', (e) => _fetchSummaryData());
  }

  @override
  void dispose() {
    PBService.pb.collection('persons').unsubscribe('*');
    PBService.pb.collection('products').unsubscribe('*');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isKioskMode) {
      return Scaffold(
        body: KioskView(
          onDismiss: () => setState(() => _isKioskMode = false),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        bool isDesktop = constraints.maxWidth > 1000;
        bool isMobile = constraints.maxWidth <= 650;

        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),
          body: Row(
            children: [
              if (!isMobile) _buildNavRail(isDesktop),
              Expanded(
                child: Column(
                  children: [
                    if (!isMobile) DragToMoveArea(child: _buildHeader()),
                    _buildSummaryRow(isMobile),
                    // [수정] _buildSearchRow()를 여기서 제거했습니다.
                    // 이제 각 페이지(Body) 내부에서 각자 검색바를 그립니다.
                    Expanded(
                      child: _buildBody(isMobile),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavRail(bool extended) {
    return NavigationRail(
      selectedIndex: _selectedIndex,
      extended: extended,
      onDestinationSelected: (i) => setState(() => _selectedIndex = i),
      backgroundColor: Colors.white,
      destinations: const [
        NavigationRailDestination(icon: FaIcon(FontAwesomeIcons.chartPie, size: 20), label: Text('대시보드')),
        NavigationRailDestination(icon: FaIcon(FontAwesomeIcons.users, size: 20), label: Text('인원관리')),
        NavigationRailDestination(icon: FaIcon(FontAwesomeIcons.microchip, size: 20), label: Text('장치관리')),
        NavigationRailDestination(icon: FaIcon(FontAwesomeIcons.boxesStacked, size: 20), label: Text('물품관리')),
        NavigationRailDestination(icon: FaIcon(FontAwesomeIcons.clockRotateLeft, size: 20), label: Text('출입기록')),
        NavigationRailDestination(icon: FaIcon(FontAwesomeIcons.gears, size: 20), label: Text('설정')),
      ],
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: IconButton(
          icon: const Icon(Icons.lock_outline),
          onPressed: () => setState(() => _isKioskMode = true),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('RFID 관리 시스템', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (Platform.isWindows)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.redAccent),
              onPressed: () => windowManager.close(),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(bool isMobile) {
    if (_selectedIndex == 1) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(26, 15, 26, 5),
        child: Row(
          children: [
            StatCard(title: "전체 인원", value: personList.length.toString(), color: Colors.blue, isMobile: isMobile, icon: FontAwesomeIcons.users),
            const SizedBox(width: 12),
            StatCard(title: "정상 등록", value: personList.where((p) => p.tagId.isNotEmpty).length.toString(), color: Colors.green, isMobile: isMobile, icon: FontAwesomeIcons.idCard),
          ],
        ),
      );
    } else if (_selectedIndex == 3) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(26, 15, 26, 5),
        child: Row(
          children: [
            StatCard(title: "품명 수", value: productList.length.toString(), color: Colors.orange, isMobile: isMobile, icon: FontAwesomeIcons.box),
            const SizedBox(width: 12),
            StatCard(title: "전체 재고", value: productList.fold<int>(0, (sum, p) => sum + p.quantity).toString(), color: Colors.blueAccent, isMobile: isMobile, icon: FontAwesomeIcons.warehouse),
          ],
        ),
      );
    }
    return const SizedBox();
  }

  Widget _buildBody(bool isMobile) {
    switch (_selectedIndex) {
      case 1:
        return PersonPage(
          searchQuery: "", // 각 페이지 내부에서 검색바를 관리하므로 빈 값 전달
          filter: '전체',
          isMobile: isMobile,
          baseUrl: _pbBaseUrl,
          onEdit: (person) => _showPersonForm(person),
        );
      case 2:
        return const Center(child: Text("장치 관리 화면 (준비 중)"));
      case 3:
        return ProductPage(
          searchQuery: "",
          isMobile: isMobile,
          baseUrl: _pbBaseUrl,
          onEdit: (product) => _showProductForm(product),
        );
      default:
        return const Center(child: Text("준비 중인 화면입니다."));
    }
  }

  void _showPersonForm(Person person) {
    debugPrint("인원 정보 수정 호출: ${person.name}");
  }

  void _showProductForm(ProductModel product) {
    debugPrint("물품 정보 수정 호출: ${product.name}");
  }
}