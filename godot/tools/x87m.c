/*
 * «Математика Windows-сборки» для проверки на Linux (пакет GТ; run_tests.sh, раздел «математика
 * Windows-сборки»). Выгруженная Windows-сборка Godot собрана MinGW: её sin, cos и atan2 считает x87
 * (fsin, fcos, fpatan — видно в самой сборке, objdump), и в последнем бите они расходятся с glibc.
 * Эта библиотека подменяет их через LD_PRELOAD теми же инструкциями x87. Проверено: с ней --selftest
 * на Linux дал ровно отпечаток боя Windows из CI (6acf30ec42df922a, прогон 39395472501), когда модель
 * ещё звала библиотеку C. Сборка: gcc -O2 -shared -fPIC -o x87m.so x87m.c -lm
 */
#include <math.h>

static long double xsin(long double x) {
	long double r;
	__asm__ __volatile__("fsin" : "=t"(r) : "0"(x));
	return r;
}

static long double xcos(long double x) {
	long double r;
	__asm__ __volatile__("fcos" : "=t"(r) : "0"(x));
	return r;
}

double sin(double x) {
	if (isnan(x) || isinf(x)) return NAN;
	return (double)xsin((long double)x);
}

double cos(double x) {
	if (isnan(x) || isinf(x)) return NAN;
	return (double)xcos((long double)x);
}

void sincos(double x, double *s, double *c) {
	*s = sin(x);
	*c = cos(x);
}

double atan2(double y, double x) {
	long double r;
	__asm__ __volatile__("fpatan" : "=t"(r) : "0"((long double)x), "u"((long double)y) : "st(1)");
	return (double)r;
}
