local I = {locale = "en"}
local ar = {
    ["Calculations"] = "حسابات", ["Calculate"] = "حساب", ["Functions"] = "دوال", ["Graph"] = "رسم",
    ["Table"] = "جدول", ["Tools"] = "أدوات", ["Back"] = "رجوع", ["Rotate"] = "تدوير", ["History"] = "السجل",
    ["Working tape"] = "سجل الحساب", ["Last answer"] = "آخر نتيجة", ["Answer"] = "النتيجة", ["Approximate"] = "تقريبي",
    ["Text"] = "نصي", ["Natural"] = "طبيعي", ["Prev field"] = "حقل سابق", ["Next field"] = "حقل تال",
    ["Clear"] = "مسح", ["Del"] = "حذف", ["Select"] = "اختيار", ["Previous"] = "السابق", ["Next"] = "التالي",
    ["Scientific keys"] = "المفاتيح العلمية", ["Equation solver"] = "حل المعادلات", ["Statistics"] = "إحصاء",
    ["Matrices"] = "مصفوفات", ["Complex numbers"] = "أعداد مركبة", ["Base converter"] = "تحويل الأساس",
    ["Units"] = "وحدات", ["Settings"] = "إعدادات", ["Edit"] = "تعديل", ["Draw"] = "ارسم", ["Enabled"] = "مفعل",
    ["Disabled"] = "معطل", ["Empty"] = "فارغ", ["Ready"] = "جاهز", ["Trace"] = "تتبع", ["Zoom in"] = "تكبير",
    ["Zoom out"] = "تصغير", ["Expand"] = "توسيع", ["Collapse"] = "طي", ["More"] = "المزيد", ["Standard"] = "قياسي",
    ["Curve"] = "منحنى", ["Analyze"] = "تحليل", ["Root"] = "جذر", ["Intersection"] = "تقاطع", ["Minimum"] = "أدنى",
    ["Maximum"] = "أقصى", ["Cancel"] = "إلغاء", ["Computing"] = "جار الحساب", ["Solve"] = "حل", ["Equation"] = "معادلة",
    ["Lower bound"] = "الحد الأدنى", ["Upper bound"] = "الحد الأعلى", ["Residual"] = "الباقي", ["Result"] = "الناتج",
    ["Mean"] = "المتوسط", ["Median"] = "الوسيط", ["Count"] = "العدد", ["Range"] = "المدى", ["Sample s"] = "انحراف العينة",
    ["Population SD"] = "انحراف المجتمع", ["Dataset"] = "البيانات", ["Rows"] = "صفوف", ["Columns"] = "أعمدة",
    ["Determinant"] = "المحدد", ["Inverse"] = "المعكوس", ["Transpose"] = "منقول", ["Real"] = "حقيقي", ["Imaginary"] = "تخيلي",
    ["Magnitude"] = "المقدار", ["Phase"] = "الزاوية", ["Number"] = "عدد", ["From"] = "من", ["To"] = "إلى",
    ["Convert"] = "تحويل", ["Retry save"] = "إعادة الحفظ", ["Exit without saving"] = "خروج دون حفظ",
    ["Language"] = "اللغة", ["Refresh"] = "تحديث الشاشة", ["Store answer"] = "حفظ النتيجة", ["Recall variable"] = "استدعاء متغير",
    ["Undo"] = "تراجع", ["Redo"] = "إعادة", ["Saved"] = "محفوظ", ["Unsaved"] = "غير محفوظ", ["Save failed"] = "تعذر الحفظ",
    ["Fill every empty field first"] = "أكمل كل الحقول الفارغة أولا", ["Division by zero"] = "قسمة على صفر",
    ["Enter an expression"] = "أدخل تعبيرا", ["Enter a value before the operator"] = "أدخل قيمة قبل العملية",
    ["Precision: 12 digits; graph: ~6"] = "الدقة: ١٢ خانة؛ الرسم: نحو ٦", ["Close"] = "إغلاق",
    ["Reset saved session"] = "إعادة تعيين الجلسة", ["Reset"] = "إعادة تعيين", ["Confirm reset"] = "تأكيد إعادة التعيين",
}
function I.t(text) return I.locale == "ar" and (ar[text] or text) or text end
return I
