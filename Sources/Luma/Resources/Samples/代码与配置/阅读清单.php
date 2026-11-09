<?php
declare(strict_types=1);

$documents = [
    ['title' => '设计文档', 'read' => true],
    ['title' => '实验记录', 'read' => false],
];

foreach ($documents as $document) {
    if (!$document['read']) {
        echo $document['title'] . PHP_EOL;
    }
}
