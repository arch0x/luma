#include <iostream>
#include <string>
#include <vector>

int main() {
    const std::vector<std::string> titles{"设计文档", "实验记录"};
    for (const auto& title : titles) {
        std::cout << title << '\n';
    }
}
