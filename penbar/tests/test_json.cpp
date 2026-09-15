#include "../src/json.h"
#include <cassert>
#include <cstdio>
int main(){
  std::wstring t = LR"({"edge":"left","mm":11.5,"push":true,"profiles":[{"name":"Кнопка \"А\"","btns":[{"k":"ctrl+z"}]}]})";
  JPtr r = JsonParse(t); assert(r && r->type==JVal::OBJ);
  assert(r->gets(L"edge")==L"left");
  assert(r->getn(L"mm")==11.5);
  assert(r->getb(L"push")==true);
  const JVal* p = r->get(L"profiles"); assert(p && p->type==JVal::ARR && p->arr.size()==1);
  assert(p->arr[0]->gets(L"name")==L"Кнопка \"А\"");
  assert(p->arr[0]->get(L"btns")->arr[0]->gets(L"k")==L"ctrl+z");
  std::wstring out; JsonWrite(r,out);
  JPtr r2 = JsonParse(out); assert(r2);
  assert(r2->gets(L"edge")==L"left" && r2->getn(L"mm")==11.5);
  assert(r2->get(L"profiles")->arr[0]->gets(L"name")==L"Кнопка \"А\"");
  assert(JsonParse(L"{ broken")==nullptr);
  assert(JsonParse(L"")==nullptr);
  assert(r->gets(L"нет",L"по умолчанию")==L"по умолчанию");
  printf("json ok\n"); return 0;
}
